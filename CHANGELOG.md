# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-02-12

### Added

- **Multi-LLM Support** — Gemini, Anthropic Claude, and OpenRouter adapters with streaming
- **Telegram Channel** — Full Telegram bot integration as the primary chat interface
- **Session Management** — Per-user conversation sessions with OTP supervision
- **SQLite Persistence** — Conversations survive restarts via Ecto + SQLite
- **Slash Commands** — `/reset`, `/status`, `/model`, `/compact`, `/help`
- **Tool System** — Extensible tool registry with bash, read, write, and edit tools
- **WebSocket Gateway** — Real-time API via Phoenix Channels
- **Phoenix Web Interface** — LiveView-based chat UI and health endpoint
- **Dynamic Model Switching** — Switch LLM providers on-the-fly with `/model`
- **Context Window Management** — Automatic compaction to stay within token limits
- **Code Quality Tooling** — Credo and Dialyxir integration via `mix check`
