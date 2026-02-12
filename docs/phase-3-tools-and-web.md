# Phase 3 — Tool Execution, WebSocket Protocol, and Web UI

## Goal

Give the agent the ability to **do things** (run commands, read/write files). Expose a WebSocket control protocol so external clients (CLI, web) can interact with the gateway. Build a WebChat + Control UI using Phoenix LiveView.

## Prerequisites

Phase 2 complete and working.

## Success Criteria

- [ ] Agent can execute bash commands and return output in conversation.
- [ ] Agent can read and write files in a workspace directory.
- [ ] WebSocket protocol allows CLI clients to send messages, list sessions, read config.
- [ ] WebChat: browser-based chat with streaming replies via LiveView.
- [ ] Control UI: dashboard showing sessions, channels, config, health.
- [ ] CLI (`clawdex`) can send messages and query status via the WS protocol.

---

## New Dependencies

```elixir
{:phoenix, "~> 1.7"},                  # Full Phoenix (replaces raw Bandit)
{:phoenix_live_view, "~> 1.0"},         # LiveView for WebChat + Control UI
{:phoenix_html, "~> 4.1"},
{:phoenix_live_reload, "~> 1.5", only: :dev},
{:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
{:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
{:heroicons, "~> 0.5"},
{:burrito, "~> 1.0", only: :prod},      # CLI binary packaging (optional)
```

---

## A. Tool Execution System

### Tool Behaviour

```elixir
defmodule Clawdex.Tool.Behaviour do
  @type tool_input :: map()
  @type tool_result :: %{output: String.t(), error: String.t() | nil, exit_code: integer() | nil}

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters_schema() :: map()   # JSON Schema for the tool's input
  @callback execute(tool_input(), context :: map()) :: {:ok, tool_result()} | {:error, term()}
end
```

### Built-in Tools

#### `Clawdex.Tool.Bash`

**Purpose:** Execute shell commands in the workspace.

**Parameters:**

```json
{
  "command": "ls -la /tmp"
}
```

**Behavior:**
- Runs command via `System.cmd/3` or `Port.open/2` (for streaming output).
- Working directory: agent workspace (default `~/.clawdex/workspace`).
- Timeout: 60 seconds (configurable).
- Captures stdout + stderr.
- Returns exit code.
- **Security:** commands run as the Elixir process user. No sandbox in Phase 3 (added in Phase 5).

#### `Clawdex.Tool.Read`

**Purpose:** Read a file's contents.

**Parameters:**

```json
{
  "path": "src/main.py",
  "start_line": 1,
  "end_line": 50
}
```

**Behavior:**
- Resolves path relative to workspace root.
- Rejects paths outside workspace (path traversal guard).
- Returns content with line numbers prefixed.
- Supports line range for large files.

#### `Clawdex.Tool.Write`

**Purpose:** Write or create a file.

**Parameters:**

```json
{
  "path": "src/main.py",
  "content": "print('hello')\n"
}
```

**Behavior:**
- Resolves path relative to workspace.
- Creates parent directories if needed.
- Rejects paths outside workspace.

#### `Clawdex.Tool.Edit`

**Purpose:** Replace a string in a file (surgical edit).

**Parameters:**

```json
{
  "path": "src/main.py",
  "old_str": "print('hello')",
  "new_str": "print('goodbye')"
}
```

### Tool Registry

```elixir
defmodule Clawdex.Tool.Registry do
  @spec list() :: [module()]
  @spec get(name :: String.t()) :: {:ok, module()} | :not_found
  @spec schemas() :: [map()]   # JSON Schema array for LLM tool_use
end
```

### Agent ↔ Tool Loop

The LLM call now uses the **tool_use** flow:

```
1. Build messages + tool definitions (from Registry.schemas()).
2. Call LLM with tools enabled.
3. If response contains tool_use blocks:
   a. For each tool call: execute via Tool.Registry.
   b. Append tool_result messages.
   c. Call LLM again with updated history (loop).
4. If response is text-only: return as final reply.
5. Max iterations: 10 (prevent infinite loops).
```

**Modified in `Clawdex.Router`:**

```elixir
defp run_agent_loop(session, messages, opts, iteration \\ 0)
  # calls LLM → checks for tool_use → executes → recurses
end
```

### Tool Policy

Simple allow/deny list in config:

```json
{
  "agent": {
    "tools": {
      "allow": ["bash", "read", "write", "edit"],
      "deny": []
    }
  }
}
```

---

## B. WebSocket Control Protocol

### Transport

Phoenix Channel on `/gateway/websocket` with a single topic: `"gateway:control"`.

### Authentication

- Token-based: client sends `{token: "..."}` on join.
- Token is set in config: `gateway.auth.token`.
- Unauthenticated joins are rejected.

### Protocol (JSON messages over Phoenix Channel)

**Request format:**

```json
{
  "method": "sessions.list",
  "params": {},
  "id": "req-1"
}
```

**Response format:**

```json
{
  "id": "req-1",
  "result": [...]
}
```

**Error format:**

```json
{
  "id": "req-1",
  "error": {"code": 404, "message": "Session not found"}
}
```

### Methods (Phase 3 subset)

| Method | Params | Result |
|---|---|---|
| `health` | `{}` | `{status, uptime, sessions, channels}` |
| `config.get` | `{key?}` | Config object (redacted secrets) |
| `sessions.list` | `{}` | `[{session_key, channel, message_count, last_active}]` |
| `sessions.reset` | `{session_key}` | `{ok: true}` |
| `sessions.delete` | `{session_key}` | `{ok: true}` |
| `channels.status` | `{}` | `[{channel, status, connected_at}]` |
| `chat.send` | `{text, session_key?}` | Streams back `chat.event` pushes |
| `chat.history` | `{session_key}` | `[{role, content, timestamp}]` |
| `models.list` | `{}` | `[{id, provider, name}]` |

### Server Push Events

| Event | Payload |
|---|---|
| `chat.event` | `{type: "text" \| "tool_use" \| "tool_result" \| "done", content, session_key}` |
| `channel.status` | `{channel, status}` |
| `session.updated` | `{session_key, message_count}` |

---

## C. Web UI (Phoenix LiveView)

### Pages

#### 1. WebChat (`/chat`)

Full-featured chat interface:

- Session selector (sidebar with existing sessions).
- Message input with send button.
- Streaming text display (LiveView streams).
- Tool execution display (collapsible tool call/result blocks).
- Model indicator in header.
- `/reset`, `/model` commands in the input.

**LiveView:** `ClawdexWeb.ChatLive`

**Implementation:**
- Connects to `"gateway:control"` channel internally (or calls Router directly).
- Uses LiveView Streams for efficient message list rendering.
- Streaming chunks arrive via `handle_info` from the Router process.

#### 2. Dashboard (`/`)

Overview page:

- Health status (green/red indicator).
- Active sessions count + list.
- Connected channels with status.
- Current model + config summary.
- Uptime.

**LiveView:** `ClawdexWeb.DashboardLive`

#### 3. Sessions (`/sessions`)

- List all sessions with metadata.
- Click to view conversation history.
- Delete / reset buttons.

**LiveView:** `ClawdexWeb.SessionsLive`

#### 4. Config (`/config`)

- Read-only display of current config (secrets redacted).
- Live reload indicator.

**LiveView:** `ClawdexWeb.ConfigLive`

### Layout

```
┌─────────────────────────────────────────────┐
│  OpenClaw        [Dashboard] [Chat] [Sessions] [Config]  │
├─────────────────────────────────────────────┤
│                                             │
│           (page content)                    │
│                                             │
└─────────────────────────────────────────────┘
```

Tailwind CSS for styling. Dark mode default.

---

## D. CLI Client

### Binary

`clawdex` — escript or Burrito-packaged binary.

### Commands

```bash
clawdex status                    # Show health + channels + sessions
clawdex send "Hello" --session main  # Send a message, print reply
clawdex sessions list             # List sessions
clawdex sessions reset <key>      # Reset a session
clawdex config get                # Print current config (redacted)
clawdex pairing approve <channel> <code>  # Approve a pairing code
```

### Implementation

- Connects to gateway via WebSocket (Phoenix Channel client).
- Uses `gateway.auth.token` for auth.
- Gateway address from config or `--gateway` flag (default `ws://localhost:4000`).

---

## Config Changes

```json
{
  "gateway": {
    "port": 4000,
    "bind": "loopback",
    "auth": {
      "token": "my-secret-token"
    }
  },
  "agent": {
    "workspace": "~/.clawdex/workspace",
    "tools": {
      "allow": ["bash", "read", "write", "edit"]
    },
    "maxToolIterations": 10
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
├── Clawdex.Pairing
├── Clawdex.Tool.Registry
├── Clawdex.Channel.Telegram (if configured)
├── Clawdex.Channel.Discord (if configured)
├── Clawdex.Channel.Slack (if configured)
├── Clawdex.Router
├── ClawdexWeb.Endpoint (Phoenix — HTTP + WS + LiveView)
│   ├── Phoenix.PubSub
│   ├── Phoenix.Presence
│   └── ClawdexWeb.GatewayChannel
└── Task.Supervisor (for tool execution tasks)
```

---

## Testing

| Test | Type |
|---|---|
| `tool/bash_test.exs` | Unit — command execution, timeout, working dir |
| `tool/read_test.exs` | Unit — file reading, line ranges, path traversal guard |
| `tool/write_test.exs` | Unit — file creation, directory creation |
| `tool/edit_test.exs` | Unit — string replacement, uniqueness check |
| `tool/registry_test.exs` | Unit — list tools, get by name, schema generation |
| `router_test.exs` (updated) | Integration — tool loop with mocked LLM |
| `gateway_channel_test.exs` | WS — protocol methods, auth, push events |
| `chat_live_test.exs` | LiveView — message send, streaming display |
| `dashboard_live_test.exs` | LiveView — health display, session count |

---

## Out of Scope for Phase 3

- Plugin system (custom tools/channels via extensions)
- Memory / RAG / vector search
- Cron / scheduled jobs
- Webhooks (inbound HTTP triggers)
- Skills platform
- Model failover / auth profile rotation
- Sandbox / Docker isolation
- Media (images, audio)
- Voice / TTS
- Browser automation
- TUI (Terminal UI) — planned for a future phase
- Companion apps (macOS/iOS/Android)