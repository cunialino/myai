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
| **llamacpp** | `llama-server` (Vulkan/RADV) serving local models on the GPU node `elcungem` | `llms` |
| **openwebui** | Chat UI (official helm chart) pointing at the local llama endpoint | `openwebui` |
| **graphiti** | Temporal knowledge-graph memory for agents (FalkorDB + MCP server) | `graphiti` |
| **ddg-search** | DuckDuckGo MCP search server | `ddg-search` |

In addition, two dedicated `llama-server` instances back Graphiti and live in
the `llms` namespace:

- **llamacpp-graphiti** — LLM for entity extraction (`qwen3-4b-2507`, port 8082)
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
| `genai.tail2f38ea.ts.net` | llama.cpp OpenAI-compatible API (via KEDA interceptor) |
| `chat.tail2f38ea.ts.net` | Open WebUI |
| `graphiti.tail2f38ea.ts.net` | Graphiti MCP server (streamable HTTP) |
| `ddg.tail2f38ea.ts.net` | DDG search MCP server |

## Architecture

{% mermaid() %}
flowchart TB
    subgraph tailnet["Tailscale tailnet"]
        genai["genai<br/>llama.cpp API"]
        chat["chat<br/>Open WebUI"]
        graphiti["graphiti<br/>MCP server"]
        ddg["ddg<br/>DDG search MCP"]
    end

    subgraph llms["llms namespace (elcungem GPU node)"]
        interceptor["KEDA HTTP interceptor<br/>+ nginx forward proxy"]
        llamacpp["llama-server<br/>chat model :8080"]
        graphiti_llm["llama-server<br/>qwen3-4b :8082"]
        embed["llama-server<br/>nomic-embed :8081"]
    end

    subgraph apps["Applications"]
        openwebui["Open WebUI<br/>CNPG pg-cluster"]
        mcp["graphiti-mcp<br/>zepai standalone"]
        falkordb["FalkorDB<br/>longhorn PVC"]
        ddgsearch["ddg-search<br/>mcp-proxy"]
    end

    genai --> interceptor
    interceptor --> llamacpp
    chat --> openwebui
    openwebui -->|OpenAI API| llamacpp
    graphiti --> mcp
    mcp -->|LLM| graphiti_llm
    mcp -->|embeddings| embed
    mcp --> falkordb
    ddg --> ddgsearch
{% end %}

#### A Note on Documentation

Most content here was drafted with AI assistance and reviewed for accuracy.
I focus my energy on coding and infrastructure — this site is a snapshot of a
live, evolving system rather than a polished product. Pull requests and
corrections are welcome.
