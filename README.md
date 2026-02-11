# Clawdex

A personal AI assistant gateway. Messages arrive on Telegram, route to LLMs (Google Gemini, OpenRouter), and replies go back. Conversations are persisted to SQLite, ensuring they survive application restarts.

Simplified Elixir port of [openclaw](https://github.com/openclaw/openclaw).

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
- `OPENROUTER_API_KEY` — falls back when `openrouter.apiKey` is missing
- `TELEGRAM_BOT_TOKEN` — falls back when `channels.telegram.botToken` is missing
- `CLAWDEX_CONFIG_PATH` — override the config file location

3. Get a Telegram bot token from [@BotFather](https://t.me/BotFather).

4. Get API keys:
   - Gemini: [aistudio.google.com](https://aistudio.google.com/)
   - OpenRouter: [openrouter.ai](https://openrouter.ai/)

## Running

```sh
mix deps.get
mix ecto.setup
mix run --no-halt
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
