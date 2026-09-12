+++
title = "Introduction"
description = "What myai deploys, and how it is wired into the homelab"
weight = 1
sort_by = "weight"

[extra]
+++

[myai](https://github.com/cunialino/myai) holds the AI-related workloads of the
homelab cluster. Everything is declarative and GitOps-driven: this repo is
registered in ArgoCD, which keeps the cluster in sync with `apps/`.

## Workloads

| App | What it is | Namespace |
|-----|-----------|-----------|
| **graphiti** | Temporal knowledge-graph memory for agents: FalkorDB, the MCP server, and the two `llama-server` helpers that back it | `graphiti` |
| **openwebui** | Chat UI (official helm chart) pointing at the Strix Halo endpoints | `openwebui` |
| **ddg-search** | DuckDuckGo MCP search server | `ddg-search` |

Chat models are **not** deployed in the cluster any more: they run on the Strix
Halo machine (`elcunhalo`, `192.168.0.6`) and the cluster consumes them as an
external LAN service. The only `llama-server` instances still hosted here are
the two small scale-to-zero helpers of the `graphiti` app:

- **llamacpp-graphiti** — LLM for entity extraction (`gpt-oss-20b`, port 8082)
- **llamacpp-embed** — embeddings for hybrid search (`nomic-embed`, port 8081)

## Layout

```
apps/            ArgoCD Application definitions (one per workload)
base/<app>/      manifests / helm values / secrets for each workload
bootstrap/       App-of-Apps to let ArgoCD pick up apps/ (apply once)
docs/            This documentation site (Zola + Goyo)
flake.nix        llama.cpp Vulkan image + dev shell
```

## Wiring into ArgoCD

1. Register this repo in ArgoCD:

   ```bash
   argocd repo add https://github.com/cunialino/myai.git
   ```

2. Apply the App-of-Apps once:

   ```bash
   kubectl apply -f bootstrap/argocd.yaml
   ```

   ArgoCD then manages everything under `apps/`.

## Access

All services are reachable through the tailnet (no public exposure):

| Host | Service |
|------|---------|
| `chat.tail2f38ea.ts.net` | Open WebUI |
| `graphiti.tail2f38ea.ts.net` | Graphiti MCP server (streamable HTTP) |
| `ddg.tail2f38ea.ts.net` | DDG search MCP server |

## Architecture

{% mermaid() %}
flowchart TB
    subgraph halo_box["Strix Halo - elcunhalo / 192.168.0.6 (outside the cluster)"]
        halo["llama.cpp<br/>chat models :11434"]
    end

    subgraph tailnet["Tailscale tailnet"]
        chat["chat<br/>Open WebUI"]
        graphiti["graphiti<br/>MCP server"]
        ddg["ddg<br/>DDG search MCP"]
    end

    subgraph gns["graphiti namespace"]
        openwebui["Open WebUI<br/>CNPG pg-cluster"]
        mcp["graphiti-mcp<br/>zepai standalone"]
        falkordb["FalkorDB<br/>longhorn PVC"]
        graphiti_llm["llama-server<br/>gpt-oss-20b :8082"]
        embed["llama-server<br/>nomic-embed :8081"]
    end

    subgraph kedans["keda namespace"]
        interceptor["HTTP interceptor<br/>+ external scaler"]
    end

    chat --> openwebui
    openwebui -->|OpenAI API| halo
    graphiti --> mcp
    mcp -->|LLM| interceptor
    mcp -->|embeddings| interceptor
    interceptor --> graphiti_llm
    interceptor --> embed
    mcp --> falkordb
    ddg --> ddgsearch
{% end %}

#### A Note on Documentation

Most content here was drafted with AI assistance and reviewed for accuracy.
I focus my energy on coding and infrastructure — this site is a snapshot of a
live, evolving system rather than a polished product. Pull requests and
corrections are welcome.
