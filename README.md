# myai

AI-related workloads for the homelab cluster, GitOps-driven via ArgoCD.

Chat models are **not** deployed here: they run on the Strix Halo machine
(`elcunhalo`, `192.168.0.6`) and the cluster consumes them as an external LAN
service. What this repo deploys:

- **graphiti** — temporal knowledge-graph memory for agents: FalkorDB, the
  standalone MCP server, and the two dedicated scale-to-zero `llama-server`
  instances (LLM + embeddings) that back it. Register it as an MCP tool server
  inside Open WebUI.
- **openwebui** — chat UI (official helm chart), pointing at the Strix Halo
  endpoints, backed by the CNPG `pg-cluster` for its database.
- **ddg-search** — DuckDuckGo MCP search server.

## Layout

```
apps/            ArgoCD Application definitions (one per workload)
base/<app>/      manifests / helm values / secrets for each workload
bootstrap/       App-of-Apps to let ArgoCD pick up apps/ (apply once)
docs/            documentation site (Zola + Goyo theme, published via GitHub Pages)
flake.nix        llama.cpp Vulkan image + dev shell
```

Namespaces: `graphiti`, `openwebui`, `ddg-search`. CNPG objects for Open WebUI
live in `cnpg-system`.

## Building & pushing the llama image

Still needed — the two graphiti helpers run `custom.io/llama-server-radv:latest`.

```bash
nix build .#dockerImage            # result -> docker-image-llama-server-radv.tar.gz
nix shell nixpkgs#skopeo -- \
  skopeo copy --insecure-policy --dest-tls-verify=false \
  docker-archive:"$(readlink result)" \
  docker://192.168.0.2:5000/llama-server-radv:latest
```

The k3s nodes mirror `custom.io -> 192.168.0.2:5000` (see `registries.yaml`), so manifests reference `custom.io/llama-server-radv:latest`.

## Wiring into ArgoCD

1. Register this repo in ArgoCD: `argocd repo add https://github.com/cunialino/myai.git`.
2. Apply the App-of-Apps once:
   ```bash
   kubectl apply -f bootstrap/argocd.yaml
   ```
   ArgoCD then manages everything under `apps/`.

## Migrating the llama servers out of `llms`

The two llama helpers used to sit in `llms` next to the chat-model deployment;
they now live in `graphiti`. PVCs are namespace-scoped, so the models claim gets
recreated. ArgoCD drives most of the cutover; two one-off `kubectl` calls have no
GitOps equivalent (the `Retain` insurance, and un-releasing the PV if it lands in
`Released`).

1. Insurance — stop the PV from being reclaimed along with the old claim:
   ```bash
   kubectl patch pv models -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
   ```

2. Delete the old Application. Removing `apps/llamacpp.yaml` from git is **not**
   enough: the app-of-apps runs with `prune: false`, so the child stays
   registered and keeps managing `llms` forever.
   ```bash
   argocd app delete llamacpp --cascade
   kubectl delete ns llms
   ```

3. Make sure the PV object is actually gone before the new app recreates it. If it
   sits in `Released` instead, its `claimRef` still points at the dead
   `llms/models-pvc` and no new claim can bind to it:
   ```bash
   kubectl get pv models
   kubectl patch pv models --type json -p '[{"op":"remove","path":"/spec/claimRef"}]'   # only if Released
   ```
   Deleting the PV outright works too — `storage.yaml` recreates it, and
   `/second_part/models` on `elcungem` is never touched.

4. Sync:
   ```bash
   argocd app diff graphiti
   argocd app sync graphiti
   argocd app wait graphiti --health
   ```
   `storage.yaml` pins `volumeName: models`, so the new `graphiti/models-pvc`
   binds to that exact PV. ArgoCD's default resource ordering already applies PV
   and PVC before the Deployments, so no sync waves are needed.

5. Verify the scale-from-zero path end to end:
   ```bash
   kubectl -n graphiti get pvc models-pvc    # Bound
   curl -s http://llamacpp-embed-svc-proxy.graphiti.svc.cluster.local:8080/v1/models
   kubectl -n graphiti get deploy llamacpp-embed llamacpp-graphiti
   ```

Skipping step 1 risks the PV being garbage-collected with the old claim and never
rebinding — statically provisioned local PVs have no provisioner.

## Placeholders to fill in

- `base/openwebui/externalsecret.yaml` — Bitwarden item UUID for the `openwebui-db` password. The matching `openwebui` role was added to `homelab/base/cnpg/cluster.yaml`.
- `base/graphiti/deployment.yaml` — `LLM__MODEL` / `EMBEDDER__MODEL` must match the `--alias` of the corresponding `llama-server` (check `curl -s http://llamacpp-graphiti-svc.graphiti.svc.cluster.local:8082/v1/models`); the embedder must expose `/v1/embeddings` for graphiti's hybrid search. FalkorDB runs as a separate deployment (`base/graphiti/falkordb.yaml`) with the `graphiti-data` PVC; the MCP server connects via `redis://falkordb.graphiti.svc.cluster.local:6379`. The `standalone` image (no bundled DB) is used, so a FalkorDB crash only restarts the DB pod.
- Tailscale hostnames are short tailnet names (`chat`, `graphiti`, `ddg`); they resolve as `<name>.tail2f38ea.ts.net` on the tailnet.
- Open WebUI model selector: the Strix Halo models appear via `models.fetch` / the OpenAI URLs. If the model supports tool calling, the Tools/MCP pages inside Open WebUI work against it.

## KEDA HTTP add-on known issues

### RBAC gap on Kubernetes >= 1.33

The KEDA HTTP add-on v0.15.0 external scaler discovers the interceptor admin endpoint via Kubernetes `Endpoints` (v1), but its ClusterRole only grants `endpointslices.discovery.k8s.io` permissions. On K8s 1.33+ the scaler fails with `there isn't any valid interceptor endpoint`, which means `isActive` is always `false` and scale-to-zero never triggers.

Fix: `base/graphiti/keda-rbac-fix.yaml` adds a separate ClusterRole + ClusterRoleBinding that grants the scaler service account `endpoints` access. ArgoCD will keep this in sync, so it survives KEDA HTTP add-on upgrades/reinstalls.

If you need an immediate manual patch (not persisted):

```bash
kubectl patch clusterrole keda-add-ons-http-external-scaler --type=json \
  -p='[{"op":"add","path":"/rules/-","value":{"apiGroups":[""],"resources":["endpoints"],"verbs":["get","list","watch"]}}]'
kubectl delete pod -n keda -l app.kubernetes.io/component=scaler
```

Verify:

```bash
kubectl port-forward -n keda svc/keda-add-ons-http-interceptor-admin 9090
curl localhost:9090/queue
```

### Tailscale ingress bypasses the interceptor (ExternalName unsupported)

The Tailscale operator resolves ingress backends by **ClusterIP + Endpoints** and does **not** support `ExternalName` services, so a scale-to-zero service cannot be exposed on the tailnet through a plain `ExternalName` alias of the interceptor — the operator keeps a stale serve-config pointing straight at the target and scaling never triggers.

Nothing in this repo hits that today: the llama helpers are in-cluster only, so their `*-svc-proxy` services stay plain `ExternalName`. If you ever expose one, add a real ClusterIP hop in front of the interceptor (nginx forward or a selectorless Service with manual `Endpoints`). See `docs/content/keda/_index.md`.

### llama.cpp preset option naming

When using `--models-preset`, the INI file must use llama.cpp CLI option names (e.g. `repeat-penalty`, not `repetition-penalty`). The preset file is at `/second_part/models/config.ini` on the `elcungem` node — the same models directory the graphiti helpers mount.
