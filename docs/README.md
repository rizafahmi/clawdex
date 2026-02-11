# OpenClaw Elixir — Phased Spec Documents

Specification documents for the Elixir port of [OpenClaw](https://github.com/openclaw/openclaw).

## Phases

| Phase | Document | Summary |
|---|---|---|
| 1 | [phase-1-mvp.md](phase-1-mvp.md) | Core gateway, Telegram channel, Anthropic LLM, session management |
| 2 | [phase-2-multi-channel.md](phase-2-multi-channel.md) | Discord + Slack channels, disk persistence, streaming, slash commands |
| 3 | [phase-3-tools-and-web.md](phase-3-tools-and-web.md) | Tool execution, WebSocket protocol, Control UI (LiveView), WebChat |
| 4 | [phase-4-plugins-and-memory.md](phase-4-plugins-and-memory.md) | Plugin system, memory/RAG, cron jobs, webhooks, skills platform |
| 5 | [phase-5-full-platform.md](phase-5-full-platform.md) | Multi-model failover, sandbox isolation, companion app protocol, voice, browser automation |

## Guiding Principles

- Each phase produces a **working, deployable system** (not a partial build).
- Leverage OTP (supervision trees, GenServers, Registry) instead of porting Node.js patterns.
- Prefer Phoenix LiveView over separate SPA frontends.
- Use Postgres (via Ecto) instead of JSON files for persistence where it makes sense.
- Each channel is a **behaviour implementation**, not a one-off integration.
