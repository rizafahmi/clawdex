# Phase 4 — Plugin System, Memory/RAG, Cron, Webhooks, and Skills

## Goal

Make the system extensible. Add a plugin architecture so new channels and tools can be added without modifying core code. Implement long-term memory (vector search), scheduled jobs (cron), inbound webhooks, and a skills platform for injecting domain-specific prompts/tools.

## Prerequisites

Phase 3 complete and working.

## Success Criteria

- [ ] A third-party developer can write a channel or tool plugin as a separate Mix package.
- [ ] Agent can search past conversations via semantic memory (`memory.search` tool).
- [ ] Cron jobs fire on schedule and deliver results to channels.
- [ ] Inbound webhooks trigger agent processing.
- [ ] Skills can be installed from workspace or a registry.
- [ ] Media (images, audio, documents) can be sent/received on channels.

---

## New Dependencies

```elixir
{:pgvector, "~> 0.3"},             # Vector similarity search (Postgres extension)
{:postgrex, "~> 0.19"},            # Postgres driver (replaces SQLite for prod)
{:quantum, "~> 3.5"},              # Cron scheduler
{:image, "~> 0.54"},               # Image processing (libvips)
{:mogrify, "~> 0.9"},              # ImageMagick wrapper (fallback)
```

---

## A. Plugin System

### Plugin Behaviour

```elixir
defmodule Clawdex.Plugin do
  @type manifest :: %{
    name: String.t(),
    version: String.t(),
    description: String.t(),
    channels: [module()],       # Channel behaviour implementations
    tools: [module()],          # Tool behaviour implementations
    hooks: [module()],          # Hook behaviour implementations
    config_schema: map() | nil  # NimbleOptions schema for plugin config
  }

  @callback manifest() :: manifest()
  @callback start(config :: map()) :: {:ok, pid()} | :ignore | {:error, term()}
  @callback stop() :: :ok
end
```

### Plugin Loader

```elixir
defmodule Clawdex.Plugin.Loader do
  @spec discover() :: [manifest()]           # Scan plugin directories
  @spec load(name :: String.t()) :: :ok      # Load + start a plugin
  @spec unload(name :: String.t()) :: :ok    # Stop + unload
  @spec loaded() :: [manifest()]             # List active plugins
end
```

**Discovery locations:**
1. Built-in plugins: compiled into the release.
2. Workspace plugins: `~/.clawdex/plugins/<name>/` (Mix project with `Clawdex.Plugin` implementation).
3. Hex packages: `{:clawdex_plugin_foo, "~> 1.0"}` in a plugin manifest file.

**Loading mechanism:**
- Plugins are OTP applications started under a dedicated supervisor.
- Plugin channels register with `Clawdex.Channel.Registry`.
- Plugin tools register with `Clawdex.Tool.Registry`.
- Plugin config is validated against the plugin's declared schema.

### Plugin Config

```json
{
  "plugins": {
    "matrix": {
      "enabled": true,
      "homeserverUrl": "https://matrix.org",
      "accessToken": "syt_..."
    },
    "weather": {
      "enabled": true,
      "apiKey": "owm-..."
    }
  }
}
```

### Example Plugin Structure

```
clawdex_plugin_weather/
├── lib/
│   ├── plugin.ex           # implements Clawdex.Plugin
│   └── tool/weather.ex     # implements Clawdex.Tool.Behaviour
├── mix.exs
└── README.md
```

---

## B. Memory / RAG (Retrieval-Augmented Generation)

### Architecture

```
                    ┌──────────────────┐
   Agent tool call  │  memory.search   │
   ─────────────►   │  memory.save     │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │  Memory.Manager  │  (GenServer)
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ Embedding │  │  Vector  │  │ Keyword  │
        │  Provider │  │  Store   │  │  Search  │
        │(OpenAI/   │  │(pgvector)│  │(Postgres │
        │ Voyage)   │  │          │  │ tsvector)│
        └──────────┘  └──────────┘  └──────────┘
```

### Schema

```elixir
schema "memories" do
  field :content, :string               # The text content
  field :source, :string                # "session:telegram:123", "file:notes.md"
  field :embedding, Pgvector.Ecto.Vector # 1536-dim vector (OpenAI) or 1024 (Voyage)
  field :metadata, :map                  # {session_key, timestamp, tags, ...}
  timestamps()
end
```

### Embedding Providers

```elixir
defmodule Clawdex.Memory.Embedding.Behaviour do
  @callback embed(text :: String.t()) :: {:ok, [float()]} | {:error, term()}
  @callback embed_batch(texts :: [String.t()]) :: {:ok, [[float()]]} | {:error, term()}
  @callback dimensions() :: integer()
end
```

Implementations:
- `Clawdex.Memory.Embedding.OpenAI` — `text-embedding-3-small` (1536 dims)
- `Clawdex.Memory.Embedding.Voyage` — `voyage-3-lite` (1024 dims)

### Memory Tools

#### `memory.search`

```json
{
  "query": "What did we discuss about the deployment last week?",
  "limit": 5
}
```

Returns top-K results by cosine similarity, with hybrid (vector + keyword) ranking.

#### `memory.save`

```json
{
  "content": "User prefers dark mode and Vim keybindings.",
  "tags": ["preferences"]
}
```

### Auto-indexing

- After each conversation turn, optionally index the exchange into memory.
- Configurable: `memory.autoIndex: true|false`.
- Session transcript sync: periodically batch-index completed sessions.

### Config

```json
{
  "memory": {
    "enabled": true,
    "provider": "openai",
    "autoIndex": false
  }
}
```

---

## C. Cron / Scheduled Jobs

### Architecture

Uses Quantum for scheduling. Jobs are persisted in the database.

### Schema

```elixir
schema "cron_jobs" do
  field :name, :string
  field :schedule, :string            # Cron expression: "0 9 * * *"
  field :prompt, :string              # System event text sent to agent
  field :agent_id, :string, default: "default"
  field :delivery_channel, :string    # "telegram:123" — where to send the result
  field :enabled, :boolean, default: true
  field :last_run_at, :utc_datetime
  field :last_result, :string
  timestamps()
end
```

### Flow

```
1. Quantum fires at scheduled time.
2. CronRunner creates/reuses a session for the job.
3. Sends the prompt to the agent (same as a user message).
4. Agent processes (may use tools).
5. Final response is delivered to delivery_channel.
6. Run is logged (timestamp, result, duration).
```

### Gateway Protocol Methods

| Method | Params | Result |
|---|---|---|
| `cron.list` | `{}` | `[{name, schedule, prompt, enabled, last_run}]` |
| `cron.add` | `{name, schedule, prompt, channel}` | `{id}` |
| `cron.update` | `{id, ...partial}` | `{ok}` |
| `cron.remove` | `{id}` | `{ok}` |
| `cron.run` | `{id}` | `{ok}` — triggers immediate run |

### Config

```json
{
  "cron": {
    "jobs": [
      {
        "name": "morning-briefing",
        "schedule": "0 9 * * *",
        "prompt": "Give me a morning briefing: weather, calendar, top news.",
        "deliverTo": "telegram:123456"
      }
    ]
  }
}
```

---

## D. Webhooks (Inbound HTTP Triggers)

### Endpoint

`POST /api/webhooks/:hook_id`

### Schema

```elixir
schema "webhooks" do
  field :hook_id, :string             # URL-safe ID
  field :secret, :string              # HMAC secret for verification
  field :prompt_template, :string     # "New GitHub issue: {{title}} — {{body}}"
  field :agent_id, :string, default: "default"
  field :delivery_channel, :string    # Where to deliver the result
  field :enabled, :boolean, default: true
  timestamps()
end
```

### Flow

```
1. External service sends POST /api/webhooks/github-issues
2. Verify HMAC signature (if secret configured).
3. Extract payload, render prompt_template with payload fields.
4. Send rendered prompt to agent.
5. Deliver response to delivery_channel.
```

### Gateway Protocol Methods

| Method | Params | Result |
|---|---|---|
| `webhooks.list` | `{}` | `[{hook_id, prompt_template, enabled}]` |
| `webhooks.create` | `{hook_id, prompt_template, channel}` | `{hook_id, url, secret}` |
| `webhooks.delete` | `{hook_id}` | `{ok}` |

---

## E. Skills Platform

### What is a Skill?

A skill is a markdown file (`SKILL.md`) that injects additional instructions, tools, or context into the agent's system prompt for specific tasks.

### Skill File Format

```markdown
---
name: code-review
description: Review code changes and provide feedback
tools: [bash, read, edit]
---

# Code Review Skill

When asked to review code:
1. Read the relevant files.
2. Identify issues: bugs, style, security.
3. Suggest improvements with specific code changes.
```

### Skill Sources

1. **Bundled:** Shipped with the release (`priv/skills/`).
2. **Workspace:** User-created in `~/.clawdex/workspace/skills/<name>/SKILL.md`.
3. **Managed:** Downloaded from a registry (future).

### Skill Loading

```elixir
defmodule Clawdex.Skill do
  @spec list() :: [skill_entry()]
  @spec load(name :: String.t()) :: {:ok, skill_content()} | {:error, :not_found}
  @spec active_for_session(session_key :: String.t()) :: [skill_content()]
end
```

Skills are injected into the system prompt at the end:

```
[base system prompt]

## Active Skills

### code-review
[skill content from SKILL.md]
```

### Skill Commands

| Command | Action |
|---|---|
| `/skills` | List available skills |
| `/skill enable <name>` | Enable a skill for this session |
| `/skill disable <name>` | Disable a skill |

---

## F. Media Pipeline

### Inbound Media

When a user sends an image/audio/document on a channel:

1. Channel adapter downloads the media to a temp file.
2. Media type is detected (MIME sniffing).
3. Images: resized to max 2048px, converted to JPEG/PNG.
4. Audio: transcribed via Whisper API (OpenAI) or Deepgram.
5. Documents (PDF): text extracted.
6. Resulting text/image is appended to the user message.

### Media Processing

```elixir
defmodule Clawdex.Media do
  @spec process(path :: String.t(), mime :: String.t()) ::
    {:ok, processed_media()} | {:error, term()}
end

defmodule Clawdex.Media.Transcription do
  @spec transcribe(audio_path :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
```

### Outbound Media

When the agent generates an image URL or file path, the channel adapter downloads and sends it as a media message.

---

## Testing

| Test | Type |
|---|---|
| `plugin/loader_test.exs` | Unit — discovery, loading, unloading |
| `memory/manager_test.exs` | Integration — embed, store, search |
| `memory/embedding_test.exs` | Unit — API calls mocked |
| `cron/service_test.exs` | Integration — schedule, fire, deliver |
| `webhook_test.exs` | Integration — HMAC verify, template render, deliver |
| `skill_test.exs` | Unit — load, parse frontmatter, inject into prompt |
| `media_test.exs` | Unit — resize, transcode, MIME detect |

---

## Out of Scope for Phase 4

- Model failover / auth profile rotation
- Sandbox / Docker isolation
- Voice / TTS / Voice Wake
- Browser automation (Playwright)
- Companion apps (macOS/iOS/Android)
- Multi-agent routing
- Canvas / A2UI
- OpenAI-compatible HTTP API
