# Clawdex

A personal AI assistant gateway. Messages arrive on Telegram, route to Google Gemini (via AI Studio), and replies go back. Conversations are tracked in-memory per chat.

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
    "model": "gemini-3.0-pro-exp",
    "systemPrompt": "You are a helpful personal assistant."
  },
  "gemini": {
    "apiKey": "your-gemini-api-key-here"
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
- `TELEGRAM_BOT_TOKEN` — falls back when `channels.telegram.botToken` is missing
- `CLAWDEX_CONFIG_PATH` — override the config file location

3. Get a Telegram bot token from [@BotFather](https://t.me/BotFather).

4. Get a Gemini API key from [aistudio.google.com](https://aistudio.google.com/).

## Running

```sh
mix deps.get
mix run --no-halt
```

A health endpoint will be available at `http://localhost:4000/health`.

## Commands

| Command   | Action                                     |
|-----------|--------------------------------------------|
| `/reset`  | Clear conversation history                 |
| `/status` | Show model name, message count, session info |

## Testing

```sh
mix test
```
