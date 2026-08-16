# myai

AI-related workloads for the homelab cluster, GitOps-driven via ArgoCD.

Deploys:
- **llamacpp** — `llama-server` (Vulkan/RADV) serving local models on the GPU node `elcungem`. Image is built from the flake and pushed to the local registry.
- **openwebui** — chat UI (official helm chart), pointing at the local llama endpoint, backed by the CNPG `pg-cluster` for its database.
- **graphiti** — temporal knowledge-graph memory for agents (FalkorDB combined image), using the local llama endpoint for LLM + embeddings. Register it as an MCP tool server inside Open WebUI.

## Layout

```
apps/            ArgoCD Application definitions (one per workload)
base/<app>/      manifests / helm values / secrets for each workload
bootstrap/       App-of-Apps to let ArgoCD pick up apps/ (apply once)
flake.nix        llama.cpp Vulkan image + dev shell
```

Namespaces: `llms` (llamacpp), `openwebui`, `graphiti`. CNPG objects for Open WebUI live in `cnpg-system`.

## Building & pushing the llama image

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

## Placeholders to fill in

- `base/openwebui/externalsecret.yaml` — Bitwarden item UUID for the `openwebui-db` password. The matching `openwebui` role was added to `homelab/base/cnpg/cluster.yaml`.
- `base/graphiti/deployment.yaml` — `MODEL_NAME` / `EMBEDDER_MODEL` must match the model id loaded by `llama-server` (check `curl -s http://llamacpp-svc.llms.svc.cluster.local:8080/v1/models`); the model must expose `/v1/embeddings` for graphiti's hybrid search.
- Tailscale hostnames are short tailnet names (`chat`, `graphiti`); they resolve as `<name>.tail2f38ea.ts.net` on the tailnet.
- Open WebUI model selector: as soon as `llamacpp` is up, the `llama-local` model appears via `models.fetch` / the OpenAI URL; pick it in the UI. If the model supports tool calling, the Tools/MCP pages inside Open WebUI work against it.