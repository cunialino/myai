+++
title = "Open WebUI"
description = "Chat UI for the local llama endpoint"
weight = 3
sort_by = "weight"

[extra]
+++

[Open WebUI](https://openwebui.com/) is the chat front-end. It is deployed
from the official helm chart and talks to the local llama endpoint over the
OpenAI-compatible API.

## Application

The ArgoCD Application ([`apps/openwebui.yaml`](https://github.com/cunialino/myai/tree/main/apps/openwebui.yaml))
is multi-source:

1. **Helm chart** — `open-webui` 16.0.0 from `https://helm.openwebui.com`,
   with values from `base/openwebui/values.yaml`.
2. **Manifests** — `base/openwebui/` (database + external secret).

## Values

Key settings in [`values.yaml`](https://github.com/cunialino/myai/tree/main/base/openwebui/values.yaml):

- `openaiBaseApiUrl: http://llamacpp-svc-proxy.llms.svc.cluster.local:8080/v1`
  — goes through the KEDA interceptor proxy, so traffic from Open WebUI
  counts toward llama.cpp's scale-to-zero.
- `openaiApiKey: no-key` — the local server does not authenticate.
- Postgres via the shared CNPG cluster: `DATABASE_TYPE=postgresql`,
  `DATABASE_HOST=pg-cluster-rw.cnpg-system.svc.cluster.local`,
  `DATABASE_NAME=openwebui`, user/password from the `openwebui-db` secret.
- Persistence: 10Gi on `longhorn-wdblack`.
- Ingress: Tailscale (`tailscale-small` proxy class), host `chat` →
  `chat.tail2f38ea.ts.net`.

## Database

- [`database.yaml`](https://github.com/cunialino/myai/tree/main/base/openwebui/database.yaml)
  creates the `openwebui` database and `openwebui` role on the
  `pg-cluster` CloudNativePG cluster (lives in `cnpg-system`; the cluster
  itself is managed by the [homelab](https://github.com/cunialino/homelab) repo).
- [`externalsecret.yaml`](https://github.com/cunialino/myai/tree/main/base/openwebui/externalsecret.yaml)
  syncs the `openwebui` role password from Bitwarden (item UUID
  `6154cea9-a770-41e6-956e-b4a800f95bb9`) via the External Secrets Operator,
  into both `cnpg-system` (with the `cnpg.io/reload` label so CNPG reloads
  credentials) and `openwebui` (consumed by the pod env).

## Usage

As soon as `llamacpp` is up, the local model appears in the model selector
(via `models.fetch` / the OpenAI URL) — pick it in the UI. If the model
supports tool calling, the Tools/MCP pages inside Open WebUI work against it.
