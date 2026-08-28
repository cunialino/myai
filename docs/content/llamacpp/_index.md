+++
title = "llama.cpp"
description = "Vulkan llama-server on the GPU node, with KEDA scale-to-zero"
weight = 2
sort_by = "weight"

[extra]
+++

[llama.cpp](https://github.com/ggml-org/llama.cpp) serves the local models.
The `llamacpp` workload runs `llama-server` on the GPU node `elcungem` and
scales to zero when idle via the [KEDA HTTP add-on](https://keda.sh/docs/latest/concepts/http-add-on/).

## Building the image

The server image is built with Vulkan enabled (Mesa/RADV, since AMDVLK is
deprecated) by the flake:

```bash
nix build .#dockerImage            # result -> docker-image-llama-server-radv.tar.gz
nix shell nixpkgs#skopeo -- \
  skopeo copy --insecure-policy --dest-tls-verify=false \
  docker-archive:"$(readlink result)" \
  docker://192.168.0.2:5000/llama-server-radv:latest
```

The k3s nodes mirror `custom.io -> 192.168.0.2:5000` (see `registries.yaml`
in the [homelab](https://github.com/cunialino/homelab) repo), so manifests
reference `custom.io/llama-server-radv:latest`.

The flake also provides a dev shell with the Vulkan RADV environment and
`huggingface-hub` for downloading models:

```bash
nix develop
```

## Deployment

Defined in [`base/llamacpp/llama.yaml`](https://github.com/cunialino/myai/tree/main/base/llamacpp/llama.yaml):

- **PV/PVC** — 500Gi local volume at `/second_part/models` on `elcungem`
  (`local-storage`), holding the GGUF models and the preset file.
- **Deployment** — pinned to `elcungem`, `privileged` with `/dev/dri` mounted
  for GPU access. Key `llama-server` flags:

  | Flag | Value | Why |
  |------|-------|-----|
  | `--models-preset` | `/second_part/models/config.ini` | Sampling params live in an INI file on the node |
  | `--models-max` | `1` | One model loaded at a time |
  | `-ngl` | `999` | Offload all layers to the GPU |
  | `-t` | `8` | CPU threads for the residual CPU work |
  | `-fa` | `on` | Flash attention |
  | `-ctk` / `-ctv` | `q4_0` | Quantized KV cache |
  | `--cache-prompt` | | Reuse prompt cache across requests |
  | `--slot-save-path` | `/tmp/llama-cache` | Persist slot state |

  Resources: 10Gi/100m requested, 30Gi/1 CPU limited.
- **Service** — `llamacpp-svc` (ClusterIP, port 8080).
- **Ingress** — Tailscale ingress (`tailscale-stream` proxy class) for
  `genai.tail2f38ea.ts.net`, pointing at `llamacpp-svc-proxy` (see below).

The preset INI must use llama.cpp **CLI option names** (e.g. `repeat-penalty`,
not `repetition-penalty`) — see [KEDA known issues](/keda/).

## Scale-to-zero

{% mermaid() %}
flowchart LR
    client["Client<br/>genai.tail2f38ea.ts.net"] --> ingress["Tailscale ingress"]
    ingress --> proxy["llamacpp-svc-proxy<br/>ClusterIP"]
    proxy --> nginx["keda-interceptor-forward<br/>nginx"]
    nginx --> interceptor["KEDA HTTP interceptor<br/>(keda ns)"]
    interceptor --> scaler["external scaler<br/>pushes activity"]
    scaler --> scaledobject["ScaledObject<br/>min 0 / max 1"]
    scaledobject -->|scales up| llamacpp["llama-server<br/>elcungem"]
    interceptor --> llamacpp
{% end %}

- **`InterceptorRoute`** (`base/llamacpp/keda.yaml`) — routes the hosts
  `genai`, `genai.tail2f38ea.ts.net`, and `llamacpp-svc-proxy.llms(.svc...)`
  through the interceptor; scaling metric is concurrency (target 100), with
  generous timeouts (readiness 300s, request 900s) since LLM generation is
  slow.
- **`ScaledObject`** — scales the `llamacpp` Deployment from 0 to 1 replica
  using the `external-push` trigger (the HTTP add-on scaler at
  `keda-add-ons-http-external-scaler.keda:9090`), with a 1200s cooldown.
- **`llamacpp-svc-proxy`** (`base/llamacpp/proxy.yaml`) — a ClusterIP Service
  backed by a small always-on nginx deployment
  (`nginxinc/nginx-unprivileged:1.29-alpine`) that forwards to the KEDA
  interceptor proxy. nginx keeps the original `Host` header, which is how the
  interceptor routes by `InterceptorRoute` host. This exists because the
  Tailscale operator cannot resolve `ExternalName` backends — see
  [KEDA known issues](/keda/).
- **RBAC fix** (`base/llamacpp/keda-rbac-fix.yaml`) — grants the scaler
  service account `endpoints` access, working around a KEDA HTTP add-on bug
  on Kubernetes ≥ 1.33.

## Verifying

```bash
# Model list from the in-cluster service
curl -s http://llamacpp-svc.llms.svc.cluster.local:8080/v1/models

# Interceptor queue (should show activity after a request)
kubectl port-forward -n keda svc/keda-add-ons-http-interceptor-admin 9090
curl localhost:9090/queue
```
