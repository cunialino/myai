+++
title = "Open WebUI"
description = "Chat UI for the Strix Halo model endpoints"
weight = 3
sort_by = "weight"

[extra]
+++

[Open WebUI](https://openwebui.com/) is the chat front-end. It is deployed
from the official helm chart and talks to the Strix Halo machine over the
OpenAI-compatible API.

## Application

The ArgoCD Application ([`apps/openwebui.yaml`](https://github.com/cunialino/myai/tree/main/apps/openwebui.yaml))
is multi-source:

1. **Helm chart** — `open-webui` 16.0.0 from `https://helm.openwebui.com`,
   with values from `base/openwebui/values.yaml`.
2. **Manifests** — `base/openwebui/` (database + external secret).

## Values

Key settings in [`values.yaml`](https://github.com/cunialino/myai/tree/main/base/openwebui/values.yaml):

- `openaiBaseApiUrls` — a single OpenAI-compatible endpoint: `:11434` on the
  Strix Halo box (`192.168.0.6`), where `llama-swap` now serves every model.
  Nothing in-cluster any more — the `llms` namespace llama server and the old
  `:8731` listener are both gone. A stale URL cannot be left here as a
  "disabled" entry: Open WebUI fetches all URLs in parallel and waits for each,
  so a dead one stalls every model-list refresh.
- `openaiApiKeys: [no-key]` — one key per URL, same order; the local server
  does not authenticate. The two lists must stay the same length.
- Postgres via the shared CNPG cluster: `DATABASE_TYPE=postgresql`,
  `DATABASE_HOST=pg-cluster-rw.cnpg-system.svc.cluster.local`,
  `DATABASE_NAME=openwebui`, user/password from the `openwebui-db` secret.
- Persistence: 10Gi on `longhorn-wdblack`.
- Ingress: Tailscale (`tailscale-stream` proxy class, 1 CPU/512Mi — the
  `tailscale-small` 10m CPU limit throttled `tailscaled` enough to break
  control-plane handshakes and WebSocket heartbeats, causing proxy crash
  loops and browser reconnect loops), host `chat` → `chat.tail2f38ea.ts.net`.

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

The Strix Halo endpoint is always on, so its models appear in the model
selector right away (via `models.fetch` / the OpenAI URL) — pick one in the UI.
`llama-swap` serves them lazily: the first request for a model that is not the
loaded one swaps processes, so that request pays the load time and the previous
model is unloaded. Model ids and aliases are whatever `llama-swap` publishes on
`/v1/models`; Open WebUI discovers them live (`model_ids` is deliberately left
empty, because setting it makes Open WebUI ignore the endpoint's own list).
If the model supports tool calling, the Tools/MCP pages inside Open WebUI work
against it.
