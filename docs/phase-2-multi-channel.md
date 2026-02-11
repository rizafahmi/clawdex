# Phase 2 — Persistence, Streaming, and OpenRouter

## Goal

Add disk-based session persistence so conversations survive restarts. Implement streaming responses so users see text arrive incrementally. Add OpenRouter as a second LLM provider for access to a wide range of models (Claude, GPT, Llama, Mistral, etc.). Add a model resolver so users can switch models on the fly.

## Prerequisites

Phase 1 complete and working (Telegram + Gemini).

## Success Criteria

- [ ] Sessions are persisted to SQLite (survive application restarts).
- [ ] Streaming: Telegram shows chunked replies (edit-in-place).
- [ ] OpenRouter provider works alongside Gemini (per-config model selection).
- [ ] `Clawdex.LLM.Resolver` maps model strings to provider modules.
- [ ] `/model <name>` switches the model for the current session.
- [ ] `/compact` summarizes old messages to free context window.
- [ ] Context window management prevents exceeding model limits.

---

## New Dependencies

```elixir
{:exqlite, "~> 0.23"},            # SQLite3 via Ecto adapter
{:ecto_sqlite3, "~> 0.17"},       # Ecto adapter for SQLite
{:ecto, "~> 3.12"},               # Schema + query layer for persistence
```

---

## New / Modified Modules

### 1. `Clawdex.LLM.OpenRouter`

**Purpose:** OpenRouter API client — a single provider for Claude, GPT, Llama, Mistral, and dozens more.

**API:** `POST https://openrouter.ai/api/v1/chat/completions`

**Interface:** Implements `Clawdex.LLM.Behaviour`.

**Details:**
- OpenAI-compatible format: messages with `role` + `content`.
- System prompt is a message with `role: "system"`.
- Auth header: `Authorization: Bearer <key>`.
- Response path: `choices[0].message.content`.
- Streaming: `stream: true` → SSE with `data: {"choices":[{"delta":{"content":"..."}}]}`.
- Model is passed as `model` field in the request body (e.g., `"anthropic/claude-sonnet-4-20250514"`, `"openai/gpt-4o"`, `"meta-llama/llama-4-maverick"`).

**Config:**

```json
{
  "openrouter": {
    "apiKey": "sk-or-..."
  }
}
```

---

### 2. `Clawdex.LLM.Streaming`

**Purpose:** Shared streaming infrastructure for all providers.

**Interface:**

```elixir
@type chunk :: %{content: String.t(), done: boolean()}

@callback chat_stream(messages, opts, callback :: (chunk -> :ok)) ::
  {:ok, String.t()} | {:error, term()}
```

**Behavior:**
- Gemini: SSE stream, parse `candidates[0].content.parts[0].text` per chunk.
- OpenRouter: SSE stream, `choices[0].delta.content` per chunk.
- Callback is invoked per chunk; the channel adapter decides how to render (edit-in-place).
- Final full text is returned for session persistence.

---

### 3. `Clawdex.LLM.Resolver`

**Purpose:** Given a model string, resolve which provider module + model ID to use.

**Interface:**

```elixir
@spec resolve(model_string :: String.t(), config :: Config.Schema.t()) ::
  {:ok, {module(), model_id :: String.t(), opts :: keyword()}} | {:error, :unknown_provider}

# Examples:
resolve("gemini/gemini-2.5-flash", config)
# => {:ok, {Clawdex.LLM.Gemini, "gemini-2.5-flash", [api_key: "..."]}}

resolve("anthropic/claude-sonnet-4-20250514", config)
# => {:ok, {Clawdex.LLM.OpenRouter, "anthropic/claude-sonnet-4-20250514", [api_key: "sk-or-..."]}}

resolve("openai/gpt-4o", config)
# => {:ok, {Clawdex.LLM.OpenRouter, "openai/gpt-4o", [api_key: "sk-or-..."]}}

resolve("meta-llama/llama-4-maverick", config)
# => {:ok, {Clawdex.LLM.OpenRouter, "meta-llama/llama-4-maverick", [api_key: "sk-or-..."]}}
```

**Rules:**
- `"gemini/"` prefix or bare `"gemini-*"` → `Clawdex.LLM.Gemini` (direct, uses Gemini API key).
- Everything else → `Clawdex.LLM.OpenRouter` (pass model string as-is).

---

### 4. `Clawdex.Session.Store` (Ecto + SQLite)

**Purpose:** Persist sessions and messages to SQLite so they survive restarts.

**Schema:**

```elixir
# sessions table
schema "sessions" do
  field :session_key, :string     # "telegram:12345"
  field :channel, :string         # "telegram"
  field :chat_id, :string         # "12345"
  field :model_override, :string  # nil = use default from config
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

**DB location:** `~/.clawdex/data/clawdex.db`

---

### 5. Slash Commands (expanded)

| Command | Action |
|---|---|
| `/reset` | Clear session history |
| `/status` | Show model, message count, session age |
| `/model <name>` | Switch model for this session (e.g., `/model openai/gpt-4o`) |
| `/model` | Show current model |
| `/compact` | Summarize old messages to free context window |
| `/help` | List available commands |

---

### 6. `Clawdex.Router` (updated)

**Changes:**
- Use `Clawdex.LLM.Resolver` to pick provider based on model string.
- Support per-session model overrides (stored in session state + SQLite).
- Handle `/model` command to switch models mid-session.
- Pass streaming callback when streaming is enabled.

---

## Streaming Implementation Detail

### Telegram strategy

| Channel | Strategy | Update interval |
|---|---|---|
| Telegram | `editMessageText` on the initial reply | Every 500ms or 100 chars |

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
    "model": "gemini/gemini-2.5-flash",
    "systemPrompt": "You are a helpful assistant.",
    "maxHistoryMessages": 50,
    "contextWindowPercent": 80
  },
  "gemini": {
    "apiKey": "AIza..."
  },
  "openrouter": {
    "apiKey": "sk-or-..."
  },
  "channels": {
    "telegram": {
      "botToken": "123:ABC"
    }
  }
}
```

---

## Supervision Tree (updated)

```
Clawdex.Application
├── Clawdex.Config.Loader
├── Clawdex.Repo (Ecto — SQLite)
├── Clawdex.Session.DynamicSupervisor
├── Clawdex.Session.Registry
├── Clawdex.Channel.Telegram
├── Clawdex.Router
└── Bandit (health endpoint)
```

---

## Testing

| Test | Type |
|---|---|
| `llm/openrouter_test.exs` | Unit (mocked HTTP) |
| `llm/streaming_test.exs` | Unit — SSE parsing, chunk accumulation |
| `llm/resolver_test.exs` | Unit — model string → provider mapping |
| `session/store_test.exs` | Integration — SQLite persistence round-trip |
| `router_test.exs` (updated) | Integration — model switching, streaming |

---

## Out of Scope for Phase 2

- Additional channels (Discord, Slack)
- DM pairing / allowlists
- Tool execution (bash, browser, etc.)
- WebSocket control protocol (CLI ↔ gateway)
- Web UI / WebChat
- Plugin system
- Media (images, audio, video)
- Cron / scheduled jobs
- Webhooks
- Workspace files (SOUL.md, MEMORY.md, etc.)
