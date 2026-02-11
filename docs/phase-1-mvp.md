# Phase 1 — MVP: Core Gateway + Telegram + LLM

## Goal

A working personal AI assistant: messages arrive on Telegram, route to Anthropic Claude, and replies go back. Conversations are tracked in-memory per chat. The system runs as a single Elixir release.

## Success Criteria

- [ ] Send a Telegram message → get an AI response back within seconds.
- [ ] Conversation history is maintained per chat (multi-turn).
- [ ] `/reset` clears the session. `/status` shows model + session info.
- [ ] Config is loaded from `~/.openclaw_ex/config.json` at startup.
- [ ] Application survives channel crashes (supervisor restarts the adapter).

---

## Project Setup

```
openclaw_ex/
├── lib/
│   ├── openclaw_ex/
│   │   ├── application.ex          # OTP Application + supervision tree
│   │   ├── config/
│   │   │   ├── loader.ex           # Read + parse JSON config
│   │   │   └── schema.ex           # Config struct + validation
│   │   ├── session/
│   │   │   ├── session.ex          # GenServer: one per conversation
│   │   │   ├── registry.ex         # DynamicSupervisor + Registry
│   │   │   └── message.ex          # Message struct (role, content, timestamp)
│   │   ├── llm/
│   │   │   ├── behaviour.ex        # @callback chat(messages, opts) :: {:ok, response} | {:error, term}
│   │   │   ├── anthropic.ex        # Anthropic Messages API client
│   │   │   └── types.ex            # LLM request/response structs
│   │   ├── channel/
│   │   │   ├── behaviour.ex        # @callback handle_message, send_reply
│   │   │   └── telegram.ex         # Telegram bot adapter
│   │   └── router.ex               # Inbound dispatch: channel → session → LLM → reply
│   └── openclaw_ex.ex              # Top-level module
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   └── runtime.exs                 # Reads env vars at release boot
├── test/
│   ├── openclaw_ex/
│   │   ├── config/loader_test.exs
│   │   ├── session/session_test.exs
│   │   ├── llm/anthropic_test.exs
│   │   ├── router_test.exs
│   │   └── channel/telegram_test.exs
│   └── test_helper.exs
├── mix.exs
└── .formatter.exs
```

---

## Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:req, "~> 0.5"},             # HTTP client (for LLM API calls)
    {:jason, "~> 1.4"},           # JSON encoding/decoding
    {:telegex, "~> 1.8"},         # Telegram Bot API (or {:ex_gram, "~> 0.53"})
    {:plug, "~> 1.16"},           # Minimal HTTP (health endpoint)
    {:bandit, "~> 1.5"},          # HTTP server (for health endpoint + future webhook)
    {:nimble_options, "~> 1.1"},  # Config validation
  ]
end
```

---

## Module Specifications

### 1. `OpenClawEx.Config.Loader`

**Purpose:** Load the user's config file at startup.

**Config file location:** `~/.openclaw_ex/config.json` (or `OPENCLAW_CONFIG_PATH` env var).

**Minimal config shape:**

```json
{
  "agent": {
    "model": "anthropic/claude-sonnet-4-20250514",
    "systemPrompt": "You are a helpful personal assistant."
  },
  "anthropic": {
    "apiKey": "sk-ant-..."
  },
  "channels": {
    "telegram": {
      "botToken": "123456:ABCDEF"
    }
  }
}
```

**Interface:**

```elixir
@spec load() :: {:ok, Config.t()} | {:error, term()}
@spec load(path :: String.t()) :: {:ok, Config.t()} | {:error, term()}
```

**Behavior:**
- Reads JSON file, parses into `Config` struct.
- Validates required fields (`agent.model`, at least one channel, at least one LLM key).
- Falls back to env vars: `ANTHROPIC_API_KEY`, `TELEGRAM_BOT_TOKEN`.
- Stored in a named GenServer (or persistent_term) for global read access.

---

### 2. `OpenClawEx.Session`

**Purpose:** GenServer that holds conversation history for one chat.

**State:**

```elixir
%Session{
  session_key: String.t(),        # e.g., "telegram:12345" or "telegram:group:-100123"
  messages: [Message.t()],        # ordered list of {role, content} turns
  model: String.t(),              # model override (nil = use default)
  created_at: DateTime.t(),
  last_active_at: DateTime.t()
}
```

**Interface:**

```elixir
@callback start_link(session_key) :: GenServer.on_start()
@callback append(pid, Message.t()) :: :ok
@callback get_history(pid) :: [Message.t()]
@callback reset(pid) :: :ok
@callback get_info(pid) :: map()
```

**Behavior:**
- Each session is a GenServer under `OpenClawEx.Session.Registry` (DynamicSupervisor).
- Sessions are identified by `{channel, chat_id}` tuple → string key.
- Idle timeout: terminate after 30 minutes of inactivity (configurable). Re-created on next message.
- Max history: keep last N messages (default 50) to avoid unbounded growth.

---

### 3. `OpenClawEx.Session.Registry`

**Purpose:** Start, find, and supervise Session GenServers.

**Interface:**

```elixir
@spec get_or_start(session_key :: String.t()) :: {:ok, pid()}
@spec lookup(session_key :: String.t()) :: {:ok, pid()} | :not_found
@spec stop(session_key :: String.t()) :: :ok
@spec list() :: [String.t()]
```

**Implementation:**
- Uses `Registry` for name lookup + `DynamicSupervisor` for lifecycle.
- Sessions are started on-demand (first message creates the session).

---

### 4. `OpenClawEx.LLM.Behaviour`

**Purpose:** Common interface for LLM providers.

```elixir
@type message :: %{role: String.t(), content: String.t()}
@type opts :: [model: String.t(), system: String.t(), max_tokens: integer()]

@callback chat(messages :: [message()], opts :: opts()) ::
  {:ok, String.t()} | {:error, term()}
```

---

### 5. `OpenClawEx.LLM.Anthropic`

**Purpose:** Call the Anthropic Messages API.

**API:** `POST https://api.anthropic.com/v1/messages`

**Request shape:**

```json
{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 4096,
  "system": "You are a helpful assistant.",
  "messages": [
    {"role": "user", "content": "Hello"},
    {"role": "assistant", "content": "Hi there!"},
    {"role": "user", "content": "What is 2+2?"}
  ]
}
```

**Behavior:**
- Uses `Req` for HTTP.
- Sets headers: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`.
- Extracts `content[0].text` from response.
- Handles errors: 401 (bad key), 429 (rate limit → retry after backoff), 500 (server error).
- Timeout: 120 seconds (LLM calls can be slow).

---

### 6. `OpenClawEx.Channel.Behaviour`

**Purpose:** Common interface for messaging channel adapters.

```elixir
@callback start_link(config :: map()) :: GenServer.on_start()
@callback send_reply(chat_id :: term(), text :: String.t()) :: :ok | {:error, term()}
```

Inbound messages are sent to the Router via:

```elixir
OpenClawEx.Router.handle_inbound(%{
  channel: :telegram,
  chat_id: "12345",
  sender_id: "67890",
  sender_name: "Alice",
  text: "Hello!",
  timestamp: DateTime.utc_now()
})
```

---

### 7. `OpenClawEx.Channel.Telegram`

**Purpose:** Telegram bot that receives and sends messages.

**Behavior:**
- Starts a Telegex polling loop (long polling) on boot.
- Receives updates, extracts text messages.
- Forwards to `Router.handle_inbound/1`.
- Implements `send_reply/2` via Telegex API.
- Handles `/reset` and `/status` as local commands (not forwarded to LLM).

---

### 8. `OpenClawEx.Router`

**Purpose:** Central dispatch — the "brain" that wires channel → session → LLM → reply.

**Flow:**

```
1. Channel adapter calls Router.handle_inbound(message)
2. Router derives session_key from channel + chat_id
3. Router gets-or-starts Session GenServer
4. Appends user message to session
5. Reads full history from session
6. Calls LLM.Anthropic.chat(history, opts)
7. Appends assistant reply to session
8. Calls Channel.send_reply(chat_id, reply_text)
```

**Interface:**

```elixir
@spec handle_inbound(inbound_message()) :: :ok
```

**Behavior:**
- Runs the LLM call in a Task (async) so the router isn't blocked.
- If the LLM returns an error, sends an error message back to the channel.
- Handles commands (`/reset`, `/status`) before reaching the LLM.

---

## Supervision Tree

```
OpenClawEx.Application
├── OpenClawEx.Config (GenServer — holds config)
├── OpenClawEx.Session.DynamicSupervisor
├── OpenClawEx.Session.Registry (Registry)
├── OpenClawEx.Channel.Telegram (GenServer — polling loop)
├── OpenClawEx.Router (stateless, but could be GenServer for rate limiting)
└── Bandit (HTTP server — health endpoint on :4000)
```

---

## Health Endpoint

`GET /health` → `200 {"status": "ok", "uptime": 3600, "sessions": 5}`

Minimal Plug router, served by Bandit on port 4000 (configurable).

---

## Slash Commands (handled locally, not sent to LLM)

| Command | Action |
|---|---|
| `/reset` | Clear session history, reply "Session reset." |
| `/status` | Reply with model name, session message count, uptime |

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Telegram adapter crashes | Supervisor restarts it (exponential backoff) |
| LLM API returns 429 | Retry once after 2s, then reply "Rate limited, try again shortly." |
| LLM API returns 401 | Reply "API key invalid. Check config." — do not retry |
| LLM API timeout (>120s) | Reply "Request timed out." |
| Config file missing | Application refuses to start, logs clear error |
| Invalid config | Application refuses to start, logs validation errors |

---

## Testing Strategy

| Test | Type | What it verifies |
|---|---|---|
| `config/loader_test.exs` | Unit | Parses valid JSON, rejects invalid, falls back to env vars |
| `session/session_test.exs` | Unit | Append, get_history, reset, idle timeout |
| `llm/anthropic_test.exs` | Unit (mocked HTTP) | Request shape, response parsing, error handling |
| `router_test.exs` | Integration | Full flow with mocked LLM + mocked channel |
| `channel/telegram_test.exs` | Unit | Command parsing, message extraction |

Use `Mox` for mocking the LLM behaviour in router tests.

---

## Out of Scope for Phase 1

- Streaming responses (full response only)
- Multiple channels (Telegram only)
- Disk persistence (in-memory only)
- Media/images/audio
- Tool execution
- Web UI
- WebSocket protocol
- Plugin system
- Multi-model support (Anthropic only)
- Allowlists / pairing / security
