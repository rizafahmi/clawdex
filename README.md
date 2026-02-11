# Clawdex

A personal AI assistant gateway. Messages arrive on Telegram, route to Anthropic Claude, and replies go back. Conversations are tracked in-memory per chat.

Simplified Elixir port of [openclaw](https://github.com/openclaw/openclaw).

## Setup

1. Copy the example config and fill in your keys:

```sh
mkdir -p ~/.openclaw_ex
cp config/config.example.json ~/.openclaw_ex/config.json
```

2. Edit `~/.openclaw_ex/config.json` with your actual credentials:

```json
{
  "agent": {
    "model": "anthropic/claude-sonnet-4-20250514",
    "systemPrompt": "You are a helpful personal assistant."
  },
  "anthropic": {
    "apiKey": "sk-ant-your-api-key-here"
  },
  "channels": {
    "telegram": {
      "botToken": "123456789:ABCDefGHIJKlmnOPQRstUVwxYZ"
    }
  }
}
```

You can also use environment variables instead of the config file:

- `ANTHROPIC_API_KEY` — falls back when `anthropic.apiKey` is missing
- `TELEGRAM_BOT_TOKEN` — falls back when `channels.telegram.botToken` is missing
- `OPENCLAW_CONFIG_PATH` — override the config file location

3. Get a Telegram bot token from [@BotFather](https://t.me/BotFather).

4. Get an Anthropic API key from [console.anthropic.com](https://console.anthropic.com/).

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
