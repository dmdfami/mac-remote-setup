# Research: OpenClaw & GoClaw — AI Agent Frameworks

Date: 2026-03-03 | Status: Complete

---

## TL;DR

Both projects exist and are substantial. **OpenClaw** is the original — a massive, Node.js-based personal AI assistant that runs on your machine and connects to 20+ messaging channels (WhatsApp, Telegram, iMessage, Zalo, etc.), with shell execution, SSH skills, and a skill/plugin architecture. **GoClaw** is a Go rewrite — multiple independent implementations exist, all inspired by OpenClaw but built as single static binaries with lower resource usage. "GoLaw" does not exist as an AI agent; the user likely meant GoClaw.

---

## 1. OpenClaw

**GitHub:** https://github.com/openclaw/openclaw
**Website:** https://openclaw.ai
**Stars:** ~252,000 (one of the fastest-growing OSS repos ever)
**License:** MIT
**Language:** TypeScript / Node.js (Node ≥22 required)
**Formerly:** Moltbot / Clawdbot

### What it does

Personal AI assistant you self-host. Connects messaging channels you already use to LLM providers, executes tools on your machine/device, and acts as an autonomous agent.

### Architecture

- Local WebSocket gateway at `ws://127.0.0.1:18789` — the control plane
- Agent runtime (Pi agent, RPC mode) on top of gateway
- Device Nodes: optional companion apps (macOS, iOS, Android) that expose camera, screen recording, location, system notifications
- Skills system: SKILL.md files (pure Markdown + YAML frontmatter, no SDK) — teach agent how to use tools for a specific domain

### Channels Supported (20+)
WhatsApp, Telegram, Slack, Discord, Signal, iMessage/BlueBubbles, IRC, Teams, Matrix, Feishu, LINE, Mattermost, Synology Chat, Nostr, Tlon, Twitch, Zalo, WebChat

### Core Tools
- **exec** — run shell commands on gateway host or node (sandbox/gateway/node execution contexts)
- **filesystem** — read/write files
- **web** — HTTP requests, scraping
- **git** — branches, commits, tags
- **SSH skill** — remote server management via paramiko (execute commands, install software, inspect logs)
- **Docker/container** commands
- Cron scheduling, memory, browser automation

### exec Tool Security
Three execution contexts:
1. **Sandbox** (default) — isolated container
2. **Gateway** — host machine (your Mac), optional approval gates
3. **Node** — companion app or headless node

Security modes: `deny` / `allowlist` / `full`. Rejects `LD_*`/`DYLD_*` env overrides to prevent binary hijacking. `exec_approval` flag for sensitive ops. Background sessions (default 30min timeout) with PTY support.

### Relevance to mac project
- Can run on Lucy/any Mac via `npm install -g openclaw && openclaw onboard --install-daemon`
- Once running, you message it via WhatsApp/Telegram → it executes shell commands on the Mac
- SSH skill: manage remote servers from within the agent
- iMessage channel: could integrate with existing Messages keep-alive
- Effectively replaces manual `mac <name>` SSH for many tasks — "hey, check disk space on Lucy" via WhatsApp
- **Concern:** Node.js runtime, heavier (~150-400MB memory). Not ideal for always-on daemon on constrained hardware.

---

## 2. GoClaw — Three Implementations

"GoClaw" = category name for Go rewrites of OpenClaw. Three distinct repos:

---

### 2a. sausheong/goclaw — Simple, minimal

**GitHub:** https://github.com/sausheong/goclaw
**Focus:** Self-hosted, single binary, minimal deps
**Channels:** Telegram, WhatsApp, CLI
**Memory:** ~20-50MB (vs OpenClaw's 150-400MB)
**Startup:** <100ms (vs OpenClaw's 2-5s)

Architecture: single-process hub-and-spoke. All in one binary.

**Built-in tools (10):**
- bash execution, file ops, web access
- inter-agent delegation, cron, memory (BM25 search)

**Config:** JSON5 at `~/.goclaw/goclaw.json5`, hot-reload, JSONL session storage

**Best fit:** Drop-in lightweight agent daemon on any Mac/VPS. Low overhead, fast, no Node.js.

---

### 2b. nextlevelbuilder/goclaw — Enterprise/Multi-tenant

**GitHub:** https://github.com/nextlevelbuilder/goclaw
**Website:** https://goclaw.sh
**Focus:** Multi-agent orchestration, enterprise features

**Key additions over sausheong:**
- Multi-agent teams: shared task boards, peer messaging, inter-agent delegation
- Generator-evaluator feedback loops, output validation hooks
- 5-layer security, per-user workspaces, encrypted API keys
- PostgreSQL 18 + pgvector storage (or file-based standalone)
- 30+ built-in tools including browser automation, MCP protocol support, custom runtime tools via API
- Web dashboard: channel management, agent management, traces & spans viewer

**Channels:** Telegram, Discord, Zalo, Feishu/Lark, WhatsApp
**LLM providers:** 13+ including Anthropic with native prompt caching (90% cost reduction claim)

**Best fit:** If wanting a full orchestration layer with multiple specialized agents for different Macs/tasks.

---

### 2c. smallnest/goclaw — Framework-oriented

**GitHub:** https://github.com/smallnest/goclaw
**Stars:** ~299
**Focus:** Developer framework for building AI agents, OpenClaw-compatible skill system

**Key features:**
- Docker sandbox + permission controls for tool execution
- Skill system compatible with OpenClaw SKILL.md format
- Vector DB + markdown memory
- Channels: Telegram, WhatsApp, Feishu, QQ, WeChat, DingTalk, Slack, Discord, Teams
- Automatic environment gating (skills only load if required tools present)

**Best fit:** Building custom agents with more framework control.

---

## 3. Integration Potential with mac project

Current mac project: SSH + Cloudflare tunnel + AppleScript + VNC + `bin/mac` CLI manager.

| Use case | How AI agent helps | Best fit |
|---|---|---|
| Natural language commands to Lucy | "Check disk", "restart app X" → WhatsApp → shell exec on Lucy | OpenClaw or sausheong/goclaw on Lucy |
| Fleet status monitoring | Agent polls all Macs, reports anomalies | nextlevelbuilder/goclaw multi-agent |
| Scheduled tasks | Cron within agent (disk cleanup, password rotation reminder) | Any GoClaw |
| SSH fleet management | SSH skill from central agent to manage N Macs | OpenClaw SSH skill |
| Zalo integration | OpenClaw has Zalo channel natively | OpenClaw only |
| Low-resource daemon | Always-on on Lucy without slowing down | sausheong/goclaw (20-50MB) |

**Integration pattern (simplest):**
1. Install sausheong/goclaw on Lucy as a LaunchDaemon (single binary, ~20MB, <1s startup)
2. Connect to Telegram or WhatsApp
3. Config: `exec` tool pointing at Lucy's shell → same power as SSH but via chat
4. No changes to existing tunnel/SSH setup — goclaw is additive

**Integration pattern (advanced):**
1. OpenClaw on a central VPS (not on each Mac — saves resources)
2. SSH skill connects OpenClaw → each Mac via existing Cloudflare tunnels
3. One WhatsApp/Telegram interface to control entire fleet

---

## 4. "GoLaw" — Does Not Exist as AI Agent

"GoLaw" searches only returned:
- harvard-lil/olaw — legal AI RAG workbench (not relevant)
- lawglance — legal assistant (not relevant)
- opa (Open Policy Agent) — policy enforcement (not relevant)

User almost certainly meant **GoClaw**. No AI agent project named GoLaw found.

---

## Summary

| Project | Language | Stars | Memory | Best For |
|---|---|---|---|---|
| openclaw/openclaw | TypeScript | 252k | 150-400MB | Full-featured, 20+ channels, Zalo |
| sausheong/goclaw | Go | ~500 | 20-50MB | Lightweight daemon, fast startup |
| nextlevelbuilder/goclaw | Go | unknown | low | Multi-agent orchestration |
| smallnest/goclaw | Go | 299 | low | Custom agent framework |

**Recommendation for mac project:** Start with **sausheong/goclaw** on Lucy — single binary, minimal footprint, bash execution tool, Telegram/WhatsApp channels. Additive to existing setup (no replacing tunnel/SSH). If Zalo channel needed, OpenClaw is the only option.

---

## Unresolved Questions

1. Does sausheong/goclaw's bash exec tool support PTY / interactive commands (needed for some macOS tools)?
2. Can goclaw run as LaunchDaemon (root) safely, or better as LaunchAgent (user)?
3. OpenClaw iMessage channel — does it require BlueBubbles (Android relay) or native macOS Messages? If native, conflicts with keep-apps-alive daemon?
4. nextlevelbuilder/goclaw star count and maintenance activity not confirmed — may be less mature.
5. Zalo channel in OpenClaw — same Electron/encryption issues as Zalo desktop, or different API?

---

## Sources

- [openclaw/openclaw GitHub](https://github.com/openclaw/openclaw)
- [OpenClaw website](https://openclaw.ai/)
- [OpenClaw exec tool docs](https://docs.openclaw.ai/tools/exec)
- [sausheong/goclaw GitHub](https://github.com/sausheong/goclaw)
- [nextlevelbuilder/goclaw GitHub](https://github.com/nextlevelbuilder/goclaw)
- [smallnest/goclaw GitHub](https://github.com/smallnest/goclaw)
- [GoClaw website](https://goclaw.sh/)
- [awesome-openclaw](https://github.com/SamurAIGPT/awesome-openclaw)
- [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)
- [OpenClaw SSH skill](https://playbooks.com/skills/openclaw/skills/ssh)
- [Milvus OpenClaw guide](https://milvus.io/blog/openclaw-formerly-clawdbot-moltbot-explained-a-complete-guide-to-the-autonomous-ai-agent.md)
