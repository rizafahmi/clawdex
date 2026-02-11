# Phase 2 — Multi-Channel, Persistence, and Streaming

## Goal

Expand from Telegram-only to Discord + Slack. Add disk-based session persistence so conversations survive restarts. Implement streaming responses so users see text arrive incrementally. Add DM pairing (allowlists) for basic security.

## Prerequisites

Phase 1 complete and working.

## Success Criteria

- [ ] Discord bot receives DMs and group mentions, replies via Nostrum.
- [ ] Slack bot receives DMs and app mentions, replies via Slack Web API.
- [ ] Sessions are persisted to SQLite (survive application restarts).
- [ ] Streaming: Telegram/Discord/Slack show chunked replies (edit-in-place).
- [ ] Allowlist: only approved senders can trigger the bot (DM pairing flow).
- [ ] OpenAI provider works alongside Anthropic (per-config model selection).
- [ ] `/model <name>` switches the model for the current session.

---

## New Dependencies

```elixir
{:nostrum, "~> 0.10"},            # Discord bot library
{:slack_web, "~> 0.4"},           # Slack Web API (or custom Req-based)
{:exqlite, "~> 0.23"},            # SQLite3 via Ecto adapter
{:ecto_sqlite3, "~> 0.17"},       # Ecto adapter for SQLite
{:ecto, "~> 3.12"},               # Schema + query layer for persistence
```

---

## New / Modified Modules

### 1. `Clawdex.LLM.OpenAI`

**Purpose:** OpenAI Chat Completions API client.

**API:** `POST https://api.openai.com/v1/chat/completions`

**Interface:** Implements `Clawdex.LLM.Behaviour`.

**Differences from Anthropic:**
- System prompt is a message with `role: "system"` (not a top-level field).
- Auth header: `Authorization: Bearer <key>` (not `x-api-key`).
- Response path: `choices[0].message.content`.
- Streaming: `stream: true` → SSE with `data: {"choices":[{"delta":{"content":"..."}}]}`.

**Config:**

```json
{
  "openai": {
    "apiKey": "sk-...",
    "baseUrl": "https://api.openai.com/v1"
  }
}
```

---

### 2. `Clawdex.LLM.Streaming`

**Purpose:** Shared streaming infrastructure for both providers.

**Interface:**

```elixir
@type chunk :: %{content: String.t(), done: boolean()}

@callback chat_stream(messages, opts, callback :: (chunk -> :ok)) ::
  {:ok, String.t()} | {:error, term()}
```

**Behavior:**
- Anthropic: SSE stream, events of type `content_block_delta` with `delta.text`.
- OpenAI: SSE stream, `choices[0].delta.content` per chunk.
- Callback is invoked per chunk; the channel adapter decides how to render (edit-in-place, append, etc.).
- Final full text is returned for session persistence.

---

### 3. `Clawdex.Channel.Discord`

**Purpose:** Discord bot via Nostrum.

**Behavior:**
- Connects to Discord Gateway (WebSocket).
- Listens for `MESSAGE_CREATE` events.
- DM messages: always process (if sender is allowlisted).
- Guild messages: only process if bot is mentioned (`@BotName`), strip the mention before forwarding.
- Reply via `Nostrum.Api.create_message/2`.
- Streaming: edit the reply message every ~500ms with accumulated text.
- Handles slash commands: `/reset`, `/status`, `/model`.

**Config:**

```json
{
  "channels": {
    "discord": {
      "token": "MTIz...",
      "allowFrom": ["user_id_1", "user_id_2"]
    }
  }
}
```

---

### 4. `Clawdex.Channel.Slack`

**Purpose:** Slack bot via Socket Mode (app-level token) + Web API.

**Behavior:**
- Connects via Slack Socket Mode WebSocket (uses app token).
- Listens for `app_mention` and `message.im` events.
- Reply via `chat.postMessage` / `chat.update` (for streaming edits).
- Thread-aware: replies in threads if the original message was in a thread.
- Streaming: post initial message, then `chat.update` every ~500ms.

**Config:**

```json
{
  "channels": {
    "slack": {
      "botToken": "xoxb-...",
      "appToken": "xapp-..."
    }
  }
}
```

---

### 5. `Clawdex.Session.Store` (Ecto + SQLite)

**Purpose:** Persist sessions and messages to SQLite so they survive restarts.

**Schema:**

```elixir
# sessions table
schema "sessions" do
  field :session_key, :string     # "telegram:12345"
  field :channel, :string         # "telegram"
  field :chat_id, :string         # "12345"
  field :model_override, :string  # nil = use default
  field :message_count, :integer, default: 0
  timestamps()
end

# messages table
schema "messages" do
  belongs_to :session, Session
  field :role, :string            # "user" | "assistant" | "system"
  field :content, :string
  field :token_count, :integer    # estimated tokens (for context window tracking)
  timestamps(updated_at: false)
end
```

**Behavior:**
- On session start: load existing messages from SQLite (if any).
- On append: write message to SQLite synchronously.
- On reset: delete messages from SQLite, reset counter.
- GenServer still holds in-memory cache for fast reads during LLM calls.
- WAL mode for concurrent read performance.

**DB location:** `~/.clawdex/data/openclaw.db`

---

### 6. `Clawdex.Pairing`

**Purpose:** DM pairing — unknown senders receive a pairing code, owner approves via CLI or config.

**Flow:**

```
1. Unknown sender sends a DM.
2. Bot replies: "Pairing code: ABCD. Ask the owner to approve."
3. Owner runs: `clawdex pairing approve telegram ABCD`
4. Sender is added to the allowlist (persisted to SQLite).
5. Future messages from that sender are processed normally.
```

**Config:**

```json
{
  "channels": {
    "telegram": {
      "dmPolicy": "pairing",
      "allowFrom": ["owner_user_id"]
    }
  }
}
```

**Policies:**
- `"pairing"` (default): unknown senders get a code.
- `"open"`: all senders are allowed.
- `"closed"`: unknown senders are silently ignored.

**Schema:**

```elixir
schema "allowlist_entries" do
  field :channel, :string
  field :sender_id, :string
  field :sender_name, :string
  field :approved_at, :utc_datetime
end
```

---

### 7. `Clawdex.LLM.Resolver`

**Purpose:** Given a model string like `"anthropic/claude-sonnet-4-20250514"` or `"openai/gpt-4o"`, resolve which provider module + model ID to use.

**Interface:**

```elixir
@spec resolve(model_string :: String.t()) ::
  {:ok, {module(), model_id :: String.t()}} | {:error, :unknown_model}

# Examples:
resolve("anthropic/claude-sonnet-4-20250514")
# => {:ok, {Clawdex.LLM.Anthropic, "claude-sonnet-4-20250514"}}

resolve("openai/gpt-4o")
# => {:ok, {Clawdex.LLM.OpenAI, "gpt-4o"}}
```

---

### 8. Slash Commands (expanded)

| Command | Action |
|---|---|
| `/reset` | Clear session history |
| `/status` | Show model, message count, session age, channel |
| `/model <name>` | Switch model for this session (e.g., `/model openai/gpt-4o`) |
| `/model` | Show current model |
| `/compact` | Summarize old messages to free context window |
| `/help` | List available commands |

---

## Streaming Implementation Detail

### Per-channel strategy

| Channel | Strategy | Update interval |
|---|---|---|
| Telegram | `editMessageText` on the initial reply | Every 500ms or 100 chars |
| Discord | `edit_message` on the initial reply | Every 500ms or 100 chars |
| Slack | `chat.update` on the initial reply | Every 500ms or 100 chars |

### Flow

```
1. LLM.chat_stream starts, returns first chunk.
2. Channel.send_reply(chat_id, first_chunk) → get message_id.
3. Accumulate chunks in a buffer.
4. Every 500ms (or 100 chars), Channel.edit_reply(chat_id, message_id, buffer).
5. On stream end, final Channel.edit_reply with complete text.
```

**Debouncing:** Use `Process.send_after/3` for the 500ms edit timer. Cancel the timer on each new chunk; only send when the timer fires or the stream ends.

---

## Context Window Management

**Purpose:** Prevent exceeding the model's context window.

**Approach (simple):**
- Track estimated token count per message (chars / 4 as rough estimate).
- Before calling LLM, sum token counts. If > 80% of model's context window, drop oldest messages (keep system prompt + last N).
- `/compact` command: send the first half of history to the LLM with "Summarize this conversation so far", replace those messages with the summary.

---

## Config Changes

```json
{
  "agent": {
    "model": "anthropic/claude-sonnet-4-20250514",
    "systemPrompt": "You are a helpful assistant.",
    "maxHistoryMessages": 50,
    "contextWindowPercent": 80
  },
  "anthropic": {
    "apiKey": "sk-ant-..."
  },
  "openai": {
    "apiKey": "sk-..."
  },
  "channels": {
    "telegram": {
      "botToken": "123:ABC",
      "dmPolicy": "pairing",
      "allowFrom": ["owner_id"]
    },
    "discord": {
      "token": "MTIz...",
      "dmPolicy": "pairing",
      "allowFrom": ["owner_id"]
    },
    "slack": {
      "botToken": "xoxb-...",
      "appToken": "xapp-...",
      "dmPolicy": "open"
    }
  }
}
```

---

## Supervision Tree (updated)

```
Clawdex.Application
├── Clawdex.Config
├── Clawdex.Repo (Ecto — SQLite)
├── Clawdex.Session.DynamicSupervisor
├── Clawdex.Session.Registry
├── Clawdex.Pairing (GenServer — manages codes + approvals)
├── Clawdex.Channel.Telegram (if configured)
├── Clawdex.Channel.Discord (if configured — Nostrum consumer)
├── Clawdex.Channel.Slack (if configured — Socket Mode WS)
├── Clawdex.Router
└── Bandit (health endpoint)
```

Channels are started conditionally based on config — if no `discord` config, the Discord adapter is not started.

---

## Testing

| Test | Type |
|---|---|
| `llm/openai_test.exs` | Unit (mocked HTTP) |
| `llm/streaming_test.exs` | Unit — SSE parsing, chunk accumulation |
| `llm/resolver_test.exs` | Unit — model string → provider mapping |
| `channel/discord_test.exs` | Unit — mention stripping, event filtering |
| `channel/slack_test.exs` | Unit — event parsing, thread handling |
| `session/store_test.exs` | Integration — SQLite persistence round-trip |
| `pairing_test.exs` | Unit — code generation, approval, allowlist check |
| `router_test.exs` (updated) | Integration — multi-channel routing, streaming |

---

## Out of Scope for Phase 2

- Tool execution (bash, browser, etc.)
- WebSocket control protocol (CLI ↔ gateway)
- Web UI / WebChat
- Plugin system
- Media (images, audio, video)
- Cron / scheduled jobs
- Webhooks
- Model failover / auth profiles
