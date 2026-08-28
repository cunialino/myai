+++
title = "DDG Search"
description = "DuckDuckGo MCP search server"
weight = 5
sort_by = "weight"

[extra]
+++

A small [MCP](https://modelcontextprotocol.io/) server giving agents
web search via DuckDuckGo, no API key required.

## Deployment

[`deployment.yaml`](https://github.com/cunialino/myai/tree/main/base/ddg-search/deployment.yaml)
runs [`duckduckgo-mcp-server`](https://github.com/tbxark/duckduckgo-mcp-server)
through `uvx` inside the [`mcp-proxy`](https://github.com/tbxark/mcp-proxy)
image (`ghcr.io/tbxark/mcp-proxy:latest`):

```
uvx duckduckgo-mcp-server --transport streamable-http --port 8000 \
    --host 0.0.0.0 --disable-dns-rebinding-protection
```

- Service: `ddg-search` (ClusterIP, port 80 → 8000) in the `ddg-search`
  namespace.
- Ingress: Tailscale (`tailscale-small`), host `ddg` →
  `ddg.tail2f38ea.ts.net`.
- Resources: 256Mi / 250m limited.

MCP clients connect to `http://ddg.tail2f38ea.ts.net/mcp/`.
