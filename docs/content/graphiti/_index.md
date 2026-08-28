+++
title = "Graphiti"
description = "Temporal knowledge-graph memory for agents, exposed as an MCP server"
weight = 4
sort_by = "weight"

[extra]
+++

[Graphiti](https://github.com/getzep/graphiti) is a temporal knowledge-graph
memory for AI agents: episodes (content snippets) are processed by an LLM
into entities (nodes) and relationships (facts), with temporal metadata
(tracking when facts become invalid). It is registered as an MCP tool server
inside Open WebUI, so the chat agent can recall and store context.

## Architecture

{% mermaid() %}
flowchart TB
    owui["Open WebUI<br/>MCP client"] -->|streamable HTTP| mcp["graphiti-mcp<br/>zepai standalone image"]
    mcp -->|episodes, search| falkor["FalkorDB<br/>graphiti ns, longhorn PVC"]
    mcp -->|entity extraction| llm["llamacpp-graphiti<br/>qwen3-4b-2507 :8082"]
    mcp -->|embeddings| emb["llamacpp-embed<br/>nomic-embed :8081"]
    llm & emb --> keda["KEDA HTTP add-on<br/>scale-to-zero"]
{% end %}

The ArgoCD Application ([`apps/graphiti.yaml`](https://github.com/cunialino/myai/tree/main/apps/graphiti.yaml))
is multi-source: `base/graphiti`, `base/llamacpp-graphiti`, and
`base/llamacpp-embed`, all landing in the `graphiti` namespace (the two
llama servers live in `llms`).

## MCP server

[`deployment.yaml`](https://github.com/cunialino/myai/tree/main/base/graphiti/deployment.yaml)
runs the `zepai/knowledge-graph-mcp:standalone` image (no bundled DB) with
`uv run --no-sync main.py`. Configuration happens through env vars:

| Env | Value | Meaning |
|-----|-------|---------|
| `FALKORDB_URI` | `redis://falkordb.graphiti.svc.cluster.local:6379` | FalkorDB service |
| `FALKORDB_DATABASE` / `GRAPHITI_GROUP_ID` | `main` | Graph namespace |
| `SEMAPHORE_LIMIT` | `2` | Concurrent episode processing (small local LLM, keep it low) |
| `OPENAI_BASE_URL` | `http://llamacpp-graphiti-svc-proxy.llms.svc.cluster.local:8080/v1` | LLM endpoint |
| `LLM__MODEL` | `qwen3-4b-2507` | Must match the `--alias` of llamacpp-graphiti |
| `OPENAI_API_URL` | `http://llamacpp-embed-svc-proxy.llms.svc.cluster.local:8080/v1` | Embeddings endpoint |
| `EMBEDDER__MODEL` / `EMBEDDER__DIMENSIONS` | `nomic-embed` / `768` | Must match llamacpp-embed |

Both endpoints go through the KEDA interceptor proxies, so Graphiti's LLM
traffic also drives scale-to-zero of the dedicated llama servers.

Two files are patched into the image via ConfigMaps (mounted over the
in-tree sources):

- `graphiti-factories` → `/app/mcp/src/services/factories.py` — adds the
  FalkorDB database driver to the upstream factories.
- `graphiti-mcp-server` → `/app/mcp/src/graphiti_mcp_server.py` — the MCP
  server itself (tools: `add_memory`, `search_nodes`,
  `search_memory_facts`, `get_entity_edge`, `get_episodes`,
  `delete_episode`, `delete_entity_edge`, `clear_graph`, `get_status`).

The service is exposed on port 8000 via a Tailscale ingress
(`tailscale-small`), host `graphiti` → `graphiti.tail2f38ea.ts.net`. MCP
clients connect to `http://graphiti.tail2f38ea.ts.net/mcp/`.

## FalkorDB

[`falkordb.yaml`](https://github.com/cunialino/myai/tree/main/base/graphiti/falkordb.yaml)
runs `falkordb/falkordb:latest` (browser and TLS disabled) with a 20Gi
`longhorn-wdblack` PVC (`graphiti-data`) for persistence. It is a separate
deployment from the MCP server, so a FalkorDB crash only restarts the DB pod.

## Dedicated llama servers

Graphiti does not share the chat model; it has two dedicated, scale-to-zero
`llama-server` instances on `elcungem` (same image and models PVC as
[llama.cpp](/llamacpp/)):

| Server | Model | Port | Role | KEDA concurrency target |
|--------|-------|------|------|------------------------|
| `llamacpp-graphiti` | `qwen3-4b-2507-Q4_K_M.gguf` (alias `qwen3-4b-2507`) | 8082 | Entity extraction / LLM calls | 8 |
| `llamacpp-embed` | `nomic-embed-text-v1.5.Q8_0.gguf` (alias `nomic-embed`, `--pooling mean --embeddings`) | 8081 | Embeddings for hybrid search | 16 |

Both use `external-push` ScaledObjects (min 0 / max 1, 5400s cooldown) with
long request timeouts (graphiti: 7200s — episode processing chains many LLM
calls; embed: 300s). Their `*-svc-proxy` services are `ExternalName` aliases
of the KEDA interceptor proxy — safe here because only in-cluster clients
(Graphiti) use them.
