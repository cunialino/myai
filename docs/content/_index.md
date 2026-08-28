+++
template = "landing.html"

[extra]
section_order = ["hero", "features"]

[extra.hero]
title = "myai"
description = "AI-related workloads for the homelab cluster — local LLM inference, chat UI, and agent memory, GitOps-driven via ArgoCD"
badge = "K8s • GitOps • Local LLMs"
cta_buttons = [
    { text = "Get Started", url = "/introduction", style = "primary" },
    { text = "View on GitHub", url = "https://github.com/cunialino/myai", style = "secondary" },
]
[extra.features_section]
title = "Workloads"
description = "Everything runs on the homelab k3s cluster, with GPU inference on elcungem (Vulkan/RADV) and scale-to-zero via KEDA."
[[extra.features_section.features]]
title = "llama.cpp"
desc = "llama-server (Vulkan/RADV) serving local models on the GPU node, image built from the flake"
icon = "fa-solid fa-microchip"
[[extra.features_section.features]]
title = "Open WebUI"
desc = "Chat UI pointing at the local llama endpoint, backed by the CloudNativePG pg-cluster"
icon = "fa-solid fa-comments"
[[extra.features_section.features]]
title = "Graphiti"
desc = "Temporal knowledge-graph memory for agents — FalkorDB + standalone MCP server"
icon = "fa-solid fa-diagram-project"
[[extra.features_section.features]]
title = "DDG Search"
desc = "DuckDuckGo MCP search server for agents"
icon = "fa-solid fa-magnifying-glass"
+++
