# Clawdex

[![CI](https://github.com/rizafahmi/clawdex/actions/workflows/ci.yml/badge.svg)](https://github.com/rizafahmi/clawdex/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A personal AI assistant gateway built on the BEAM. Messages arrive on Telegram (or via WebSocket), route to LLMs (Gemini, Anthropic Claude, OpenRouter), and replies stream back. Conversations are persisted to SQLite, ensuring they survive restarts.

## Core Features

Clawdex leverages the Elixir/OTP platform to provide an extremely robust and efficient runtime:

- **Lightweight efficiency** — Each user conversation runs in its own isolated process, using only ~2 KB of memory. Thousands of concurrent sessions cost almost nothing.
- **Fault tolerance** — Automatic recovery from failures. A single bad LLM response or tool crash never takes down the system.
- **True Concurrency** — Messages, LLM calls, and tool executions run concurrently across all users without thread pools or locks.
- **Soft real-time** — Responsive streaming even under heavy load; no single user can starve others.
- **Low memory footprint** — The entire gateway idles at ~50 MB, making it perfect for personal VPS or Raspberry Pi.

## Architecture

```
┌──────────────────────────────────────────────┐
│                   Channels                   │
│  Telegram Bot  │  WebSocket Gateway  │  Web  │
└──────┬─────────┴──────────┬──────────┴───┬───┘
       │                    │              │
       ▼                    ▼              ▼
┌──────────────────────────────────────────────┐
│               Router / Commands              │
│     /model  /reset  /status  /compact        │
└──────────────────────┬───────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
┌────────────┐  ┌────────────┐  ┌────────────┐
│  Sessions  │  │   Tools    │  │  LLM Layer │
│ (per-user  │  │ bash,read, │  │  Gemini    │
│  GenServer)│  │ write,edit │  │  Anthropic │
│            │  │            │  │  OpenRouter│
└─────┬──────┘  └────────────┘  └────────────┘
      │
      ▼
┌────────────┐
│   SQLite   │
│ (Ecto Repo)│
└────────────┘
```

**Key modules:**

| Module | Role |
|---|---|
| `Clawdex.Session.Server` | Per-user GenServer managing conversation state |
| `Clawdex.Router` | Dispatches messages and slash commands |
| `Clawdex.Gateway` | Orchestrates LLM calls with tool loop |
| `Clawdex.LLM.*` | Provider adapters (Gemini, Anthropic, OpenRouter) |
| `Clawdex.Tool.*` | Sandboxed tool implementations |
| `Clawdex.Channel.Telegram` | Telegram bot channel |
| `ClawdexWeb.GatewayChannel` | WebSocket channel for real-time API |

## Setup

1. Copy the example config and fill in your keys:

   ```sh
   mkdir -p ~/.clawdex
   cp config/config.example.json ~/.clawdex/config.json
   ```

2. Edit `~/.clawdex/config.json` with your actual credentials:

   ```json
   {
     "agent": {
       "model": "gemini/gemini-2.5-flash",
       "systemPrompt": "You are a helpful personal assistant.",
       "maxHistoryMessages": 50,
       "contextWindowPercent": 80
     },
     "gemini": {
       "apiKey": "your-gemini-api-key-here"
     },
     "anthropic": {
       "apiKey": "your-anthropic-api-key-here"
     },
     "openrouter": {
       "apiKey": "your-openrouter-key-here"
     },
     "channels": {
       "telegram": {
         "botToken": "123456789:ABCDefGHIJKlmnOPQRstUVwxYZ"
       }
     }
   }
   ```

   You can also use environment variables instead of the config file:

   - `GEMINI_API_KEY` — falls back when `gemini.apiKey` is missing
   - `ANTHROPIC_API_KEY` — falls back when `anthropic.apiKey` is missing
   - `OPENROUTER_API_KEY` — falls back when `openrouter.apiKey` is missing
   - `TELEGRAM_BOT_TOKEN` — falls back when `channels.telegram.botToken` is missing
   - `CLAWDEX_CONFIG_PATH` — override the config file location

3. Get a Telegram bot token from [@BotFather](https://t.me/BotFather).

4. Get API keys:
   - Gemini: [aistudio.google.com](https://aistudio.google.com/)
   - Anthropic: [console.anthropic.com](https://console.anthropic.com/)
   - OpenRouter: [openrouter.ai](https://openrouter.ai/)

## Running

```sh
mix setup
mix phx.server

```

A health endpoint will be available at `http://localhost:4000/health`.

## Commands

| Command | Action |
|---|---|
| `/reset` | Clear conversation history |
| `/status` | Show model name, message count, session info |
| `/model <name>` | Switch model (e.g., `/model openai/gpt-4o`) |
| `/model` | Show current model |
| `/compact` | Summarize old messages to free context window |
| `/help` | Show available commands |

## Testing

```sh
mix test
```

## Code Quality

Run formatting, linting (Credo), and static analysis (Dialyzer):

```sh
mix check
```

## Roadmap

Clawdex is developed in phases. See the [docs/](docs/) directory for detailed specs:

| Phase | Status | Focus |
|---|---|---|
| 1 — MVP | ✅ Complete | Core gateway, Telegram, LLM adapters, sessions |
| 2 — Multi-channel | ✅ Complete | Streaming, persistence, slash commands |
| 3 — Tools & Web | 🚧 In Progress | Tool execution, WebSocket API, LiveView UI |
| 4 — Plugins & Memory | 📋 Planned | Plugin system, RAG, cron, webhooks |
| 5 — Full Platform | 📋 Planned | Multi-model failover, voice, sandbox |

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE) © Riza Fahmi

## Credits

Inspired by and simplified from [openclaw](https://github.com/openclaw/openclaw).
