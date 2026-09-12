+++
title = "KEDA"
description = "KEDA HTTP add-on: how scale-to-zero works here, and its known issues"
weight = 6
sort_by = "weight"

[extra]
+++

[KEDA](https://keda.sh/) with the [HTTP add-on](https://keda.sh/docs/latest/concepts/http-add-on/)
drives scale-to-zero for all llama servers in this repo. The add-on works by
putting an **interceptor** in front of the target service: every request is
counted, and the external scaler pushes activity to KEDA, which scales the
Deployment up (and back to zero after a cooldown).

{% mermaid() %}
flowchart LR
    req["HTTP request"] --> ing["interceptor proxy<br/>(keda ns)"]
    ing -->|counts activity| scaler["external scaler<br/>keda-add-ons-http-external-scaler:9090"]
    scaler -->|external-push| so["ScaledObject"]
    so --> deploy["target Deployment"]
    ing --> deploy
{% end %}

Each scaled workload defines an `InterceptorRoute` (which hosts route
through the interceptor, scaling metric, timeouts) and a `ScaledObject`
(`external-push` trigger pointing at the scaler). See
[Graphiti](/graphiti/) for the concrete examples.

## Known issues

### RBAC gap on Kubernetes >= 1.33

The KEDA HTTP add-on (v0.15.0) external scaler discovers the interceptor
admin endpoint via Kubernetes `Endpoints` (v1), but its ClusterRole only
grants `endpointslices.discovery.k8s.io` permissions. On K8s 1.33+ the
scaler fails with `there isn't any valid interceptor endpoint`, which means
`isActive` is always `false` and scale-to-zero never triggers.

Fix: [`base/graphiti/keda-rbac-fix.yaml`](https://github.com/cunialino/myai/tree/main/base/graphiti/keda-rbac-fix.yaml)
adds a separate ClusterRole + ClusterRoleBinding that grants the scaler
service account `endpoints` access. ArgoCD keeps it in sync, so it survives
KEDA HTTP add-on upgrades/reinstalls. It is cluster-scoped, so it lives with
the only workloads that are scaled through the add-on.

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

### Tailscale ingress cannot target the interceptor (ExternalName unsupported)

The Tailscale operator (k8s-operator) resolves ingress backends by
**ClusterIP + Endpoints**; it does **not** support `ExternalName` services.
If an ingress backend is an `ExternalName` pointing at
`keda-add-ons-http-interceptor-proxy.keda.svc.cluster.local`, the operator
logs `Ingress contains no valid backends` and keeps a **stale serve-config**
pointing straight at the target service — bypassing the interceptor, so
requests never trigger scale-to-zero and return `no route to host` when the
workload is at zero.

Exposing a scale-to-zero service on the tailnet therefore needs a real
ClusterIP in front of the interceptor: either a small always-on nginx forward
that preserves the original `Host` header (how the retired `genai` endpoint
used to work), or a selectorless Service with manually managed `Endpoints`
listing the interceptor pod IPs.

Nothing in this repo is exposed that way today: the llama servers are reached
only from inside the cluster, so their `*-svc-proxy` services can stay plain
`ExternalName` aliases of the interceptor. If you ever put one behind a
Tailscale ingress, do not reuse the `ExternalName` — add the ClusterIP hop.

### llama.cpp preset option naming

When using `--models-preset`, the INI file must use llama.cpp **CLI option
names** (e.g. `repeat-penalty`, not `repetition-penalty`). The preset file is
at `/second_part/models/config.ini` on the `elcungem` node — the same models
directory the graphiti helpers mount.
