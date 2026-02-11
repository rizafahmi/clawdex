# Phase 5 — Full Platform: Failover, Sandbox, Voice, Browser, Multi-Agent

## Goal

Bring the Elixir port to feature parity with the core TypeScript OpenClaw. Add model failover with auth profile rotation, Docker sandbox isolation, browser automation, voice/TTS, multi-agent routing, OpenAI-compatible API, and the companion app WebSocket protocol.

## Prerequisites

Phase 4 complete and working.

## Success Criteria

- [ ] Model failover: if Claude fails, auto-switch to OpenAI (and vice versa).
- [ ] Auth profiles: rotate between OAuth tokens and API keys with cooldowns.
- [ ] Sandbox: non-main sessions run tool execution inside Docker containers.
- [ ] Browser tool: agent can navigate, screenshot, and interact with web pages.
- [ ] Voice: TTS output on channels, Voice Wake trigger on companion apps.
- [ ] Multi-agent: route different channels/senders to different agent configurations.
- [ ] OpenAI-compatible API: `POST /v1/chat/completions` endpoint.
- [ ] Companion app protocol: macOS/iOS/Android apps can pair and connect.

---

## A. Model Failover & Auth Profiles

### Auth Profile System

An auth profile is a named credential set for an LLM provider:

```elixir
schema "auth_profiles" do
  field :name, :string              # "anthropic-oauth", "openai-key-1"
  field :provider, :string          # "anthropic", "openai"
  field :auth_type, :string         # "api_key", "oauth"
  field :credentials, :map          # encrypted: {api_key: "..."} or {access_token, refresh_token, expires_at}
  field :priority, :integer         # lower = preferred
  field :status, :string            # "active", "cooldown", "failed"
  field :cooldown_until, :utc_datetime
  field :last_used_at, :utc_datetime
  field :failure_count, :integer, default: 0
  timestamps()
end
```

### Failover Flow

```
1. Resolve model → provider + auth profiles (ordered by priority).
2. Try first active profile.
3. On auth error (401/403): mark profile as "failed", try next.
4. On rate limit (429): mark profile as "cooldown" (5 min), try next.
5. On server error (500/502/503): retry once after 2s, then try next.
6. On context overflow: compact session history, retry same profile.
7. If all profiles exhausted: reply with error to user.
```

### GenServer: `OpenClawEx.LLM.Failover`

```elixir
@spec chat_with_failover(messages, opts) :: {:ok, response} | {:error, :all_profiles_exhausted}
```

- Maintains profile health state in ETS for fast reads.
- Cooldown expiry checked on each call.
- Metrics: tracks success/failure counts per profile.

### Config

```json
{
  "auth": {
    "profiles": [
      {
        "name": "claude-oauth",
        "provider": "anthropic",
        "type": "oauth",
        "priority": 1
      },
      {
        "name": "openai-backup",
        "provider": "openai",
        "type": "api_key",
        "apiKey": "sk-...",
        "priority": 2
      }
    ]
  }
}
```

---

## B. Sandbox (Docker Isolation)

### Purpose

Run tool execution for non-main sessions inside Docker containers. Prevents untrusted group users from accessing the host filesystem.

### Architecture

```
                    ┌──────────────┐
                    │   Router     │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              ▼                         ▼
     ┌────────────────┐      ┌────────────────────┐
     │  Main session   │      │  Non-main session   │
     │  (direct exec)  │      │  (sandboxed exec)   │
     │                 │      │                      │
     │  Tool.Bash      │      │  Sandbox.Container   │
     │  runs on host   │      │  runs in Docker      │
     └────────────────┘      └────────────────────┘
```

### Sandbox GenServer

```elixir
defmodule OpenClawEx.Sandbox do
  @spec create(session_key :: String.t(), opts :: map()) :: {:ok, container_id}
  @spec exec(container_id, command :: String.t(), timeout :: integer()) :: {:ok, result}
  @spec destroy(container_id) :: :ok
  @spec list() :: [{session_key, container_id, created_at}]
end
```

**Behavior:**
- Uses Docker Engine API (HTTP via `/var/run/docker.sock`).
- Base image: `openclaw-sandbox:latest` (minimal Ubuntu + common tools).
- Workspace mounted as a volume (read-only for non-main, read-write for main).
- Network: disabled by default, configurable.
- Auto-cleanup: containers destroyed when session resets or times out.

### Config

```json
{
  "sandbox": {
    "mode": "non-main",
    "image": "openclaw-sandbox:latest",
    "networkEnabled": false,
    "memoryLimit": "512m",
    "cpuLimit": "1.0"
  }
}
```

---

## C. Browser Automation

### Architecture

Uses Playwright via a Node.js sidecar process (Playwright has no Elixir equivalent).

```
  Agent tool call         Port (stdin/stdout JSON)        Node.js
  ─────────────► OpenClawEx.Browser.Bridge ◄──────────► playwright-bridge.mjs
                                                          │
                                                          ▼
                                                    Chromium (CDP)
```

### Alternative: Wallaby

For simpler use cases, use Wallaby (Elixir-native ChromeDriver wrapper). Limitations: no CDP snapshots, less mature than Playwright.

### Browser Tools

| Tool | Parameters | Description |
|---|---|---|
| `browser.navigate` | `{url}` | Navigate to URL, return page title + snapshot |
| `browser.snapshot` | `{}` | Return accessibility tree snapshot of current page |
| `browser.screenshot` | `{selector?}` | Take screenshot, return as base64 |
| `browser.click` | `{selector}` | Click an element |
| `browser.type` | `{selector, text}` | Type text into an input |
| `browser.evaluate` | `{script}` | Run JavaScript, return result |

### Browser Bridge Protocol

```json
// Request (Elixir → Node.js via Port stdin)
{"id": 1, "method": "navigate", "params": {"url": "https://example.com"}}

// Response (Node.js → Elixir via Port stdout)
{"id": 1, "result": {"title": "Example Domain", "snapshot": "..."}}
```

### Config

```json
{
  "browser": {
    "enabled": true,
    "executablePath": "/usr/bin/chromium",
    "headless": true
  }
}
```

---

## D. Voice / TTS

### Text-to-Speech

```elixir
defmodule OpenClawEx.TTS do
  @spec synthesize(text :: String.t(), opts :: keyword()) :: {:ok, audio_binary} | {:error, term()}
end
```

Providers:
- **ElevenLabs:** `POST https://api.elevenlabs.io/v1/text-to-speech/:voice_id`
- **Edge TTS:** (free, via `node-edge-tts` sidecar or Elixir HTTP client)

### Voice Wake (Companion App Protocol)

The companion app (macOS/iOS) performs local speech recognition. When the wake word is detected:

1. App transcribes speech to text locally.
2. App sends `{"method": "agent", "params": {"message": "transcribed text"}}` via WS.
3. Gateway processes as normal message.
4. Response is sent back as text + TTS audio.

### Talk Mode

Continuous conversation mode:

1. App sends audio chunks via WS.
2. Gateway transcribes (Whisper API).
3. Agent processes transcribed text.
4. Response TTS audio streamed back via WS.

### Config

```json
{
  "tts": {
    "provider": "elevenlabs",
    "voiceId": "pNInz6obpgDQGcFmaJgB",
    "apiKey": "..."
  },
  "voicewake": {
    "enabled": true,
    "wakeWord": "hey claw"
  }
}
```

---

## E. Multi-Agent Routing

### Purpose

Route different channels, senders, or groups to different agent configurations (different system prompts, models, tools, workspaces).

### Config

```json
{
  "agents": {
    "default": {
      "model": "anthropic/claude-sonnet-4-20250514",
      "systemPrompt": "You are a helpful assistant.",
      "workspace": "~/.openclaw_ex/workspace"
    },
    "code-assistant": {
      "model": "anthropic/claude-sonnet-4-20250514",
      "systemPrompt": "You are an expert programmer.",
      "workspace": "~/projects",
      "tools": {"allow": ["bash", "read", "write", "edit"]}
    }
  },
  "routing": {
    "rules": [
      {"channel": "telegram", "chatId": "12345", "agent": "code-assistant"},
      {"channel": "discord", "guildId": "99999", "agent": "default"},
      {"channel": "*", "agent": "default"}
    ]
  }
}
```

### Router Changes

```elixir
defp resolve_agent(inbound_message) do
  # Match routing rules in order, return agent config.
  # Each agent has its own session namespace, workspace, tools, system prompt.
end
```

### Sub-agent Spawning

The agent can spawn a child session with a different agent config:

```
Tool: sessions_spawn
Params: {agent: "code-assistant", prompt: "Review this PR."}
Result: {session_key: "sub:code-assistant:abc123", status: "running"}
```

Sub-agent results are announced back to the parent session.

---

## F. OpenAI-Compatible HTTP API

### Purpose

Allow external tools (Cursor, Continue, etc.) to use OpenClaw as an OpenAI-compatible endpoint.

### Endpoints

| Endpoint | Description |
|---|---|
| `POST /v1/chat/completions` | Chat completions (streaming + non-streaming) |
| `GET /v1/models` | List available models |

### Chat Completions

**Request (standard OpenAI format):**

```json
{
  "model": "anthropic/claude-sonnet-4-20250514",
  "messages": [{"role": "user", "content": "Hello"}],
  "stream": true,
  "max_tokens": 4096
}
```

**Response:** Standard OpenAI SSE format with `data: {...}` chunks.

### Auth

`Authorization: Bearer <gateway-token>` (same token as WS auth).

---

## G. Companion App Protocol (Device Nodes)

### Purpose

macOS/iOS/Android apps connect to the gateway as "nodes" that expose device capabilities (camera, screen, notifications, local commands).

### Pairing Flow

```
1. App discovers gateway via Bonjour/mDNS (or manual URL entry).
2. App sends node.pair.request with device info.
3. Gateway generates pairing code, shows to owner.
4. Owner approves via CLI or WebChat.
5. App receives a long-lived device token.
6. Future connections use device token for auth.
```

### Node Protocol (over Gateway WS)

| Method | Direction | Description |
|---|---|---|
| `node.list` | Gateway → Client | List connected nodes |
| `node.describe` | Gateway → Node | Get node capabilities + permissions |
| `node.invoke` | Gateway → Node | Execute a capability (camera.snap, screen.record) |
| `node.invoke.result` | Node → Gateway | Return capability result |
| `node.event` | Node → Gateway | Push event (voice wake trigger, location update) |

### Node Capabilities

| Capability | Description |
|---|---|
| `system.run` | Run a local command on the device |
| `system.notify` | Post a notification |
| `camera.snap` | Take a photo |
| `camera.clip` | Record a short video |
| `screen.record` | Record screen |
| `location.get` | Get current GPS location |
| `canvas.push` | Push HTML/A2UI content to device display |

---

## H. Canvas / A2UI

### Purpose

Agent-driven visual workspace. The agent can push HTML/CSS/JS (or structured A2UI components) to a connected app's canvas surface.

### Tools

| Tool | Description |
|---|---|
| `canvas.push` | Push HTML content to the canvas |
| `canvas.reset` | Clear the canvas |
| `canvas.eval` | Evaluate JavaScript on the canvas |
| `canvas.snapshot` | Screenshot the canvas and return as image |

### Protocol

Canvas content is delivered via the node protocol:

```json
{
  "method": "node.invoke",
  "params": {
    "nodeId": "macbook-pro",
    "capability": "canvas.push",
    "args": {"html": "<div>...</div>"}
  }
}
```

---

## Supervision Tree (final)

```
OpenClawEx.Application
├── OpenClawEx.Config
├── OpenClawEx.Repo (Ecto — Postgres)
├── OpenClawEx.Session.DynamicSupervisor
├── OpenClawEx.Session.Registry
├── OpenClawEx.Pairing
├── OpenClawEx.LLM.Failover (auth profile management)
├── OpenClawEx.Tool.Registry
├── OpenClawEx.Plugin.Supervisor
│   ├── Plugin A (channel + tools)
│   └── Plugin B (tools)
├── OpenClawEx.Memory.Manager
├── OpenClawEx.Cron.Scheduler (Quantum)
├── OpenClawEx.Sandbox.Supervisor (Docker containers)
├── OpenClawEx.Browser.Bridge (Port to Node.js)
├── OpenClawEx.TTS
├── OpenClawEx.Node.Registry (connected device nodes)
├── Channel Supervisors
│   ├── OpenClawEx.Channel.Telegram
│   ├── OpenClawEx.Channel.Discord
│   ├── OpenClawEx.Channel.Slack
│   └── (plugin channels)
├── OpenClawEx.Router
└── OpenClawExWeb.Endpoint (Phoenix)
    ├── Phoenix.PubSub
    ├── Phoenix.Presence
    ├── GatewayChannel (control protocol)
    ├── NodeChannel (device nodes)
    ├── LiveView (WebChat + Dashboard)
    └── OpenAI HTTP API (/v1/*)
```

---

## Testing

| Test | Type |
|---|---|
| `llm/failover_test.exs` | Integration — profile rotation, cooldowns, error classification |
| `sandbox_test.exs` | Integration — Docker create/exec/destroy |
| `browser/bridge_test.exs` | Integration — Port communication, navigate, snapshot |
| `tts_test.exs` | Unit — ElevenLabs API mock |
| `routing_test.exs` | Unit — multi-agent rule matching |
| `openai_http_test.exs` | Integration — /v1/chat/completions conformance |
| `node/pairing_test.exs` | Integration — pair flow, token management |
| `canvas_test.exs` | Unit — push, reset, eval protocol messages |

---

## Feature Parity Checklist (vs TypeScript OpenClaw)

| Feature | Status |
|---|---|
| Gateway WS control plane | ✅ Phase 3 |
| Multi-channel (WA, TG, Slack, Discord, Signal, iMessage) | ✅ Phase 2 + plugins |
| AI agent runtime with tools | ✅ Phase 3 |
| Model failover + auth profiles | ✅ Phase 5 |
| Streaming responses | ✅ Phase 2 |
| Session persistence | ✅ Phase 2 |
| DM pairing / allowlists | ✅ Phase 2 |
| Cron / scheduled jobs | ✅ Phase 4 |
| Webhooks | ✅ Phase 4 |
| Plugin system | ✅ Phase 4 |
| Memory / RAG | ✅ Phase 4 |
| Skills platform | ✅ Phase 4 |
| Media pipeline | ✅ Phase 4 |
| Browser automation | ✅ Phase 5 |
| Docker sandbox | ✅ Phase 5 |
| TTS / Voice | ✅ Phase 5 |
| Multi-agent routing | ✅ Phase 5 |
| OpenAI-compatible API | ✅ Phase 5 |
| Canvas / A2UI | ✅ Phase 5 |
| Companion app protocol | ✅ Phase 5 |
| Web UI (Control + WebChat) | ✅ Phase 3 (LiveView) |
| CLI | ✅ Phase 3 |
| WhatsApp (Baileys) | ⚠️ Requires Node.js sidecar or protocol reimplementation |
| Signal (signal-cli) | ⚠️ Requires Java subprocess |
| iMessage | ⚠️ macOS-only, requires AppleScript bridge |
| macOS/iOS/Android native apps | ❌ Out of scope (keep existing Swift/Kotlin apps, connect via protocol) |
