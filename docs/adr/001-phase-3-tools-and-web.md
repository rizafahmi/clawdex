# ADR 001: Phase 3 Tools & Web UI Architecture

## Status
Accepted

## Context
Phase 3 of Clawdex introduces "Tool Execution" (allowing the agent to run commands and edit files) and a "Web UI" (WebChat + Control Dashboard). The current system is built on `Bandit` + `Plug` with a custom supervision tree. We need to decide on the framework for the Web UI, the security model for tool execution, and the internal communication architecture.

## Decisions

### 1. Adopt Phoenix Framework
*   **Decision**: Migrate from `Bandit` + `Plug` to the full **Phoenix Framework** (`~> 1.8`).
*   **Rationale**:
    *   **LiveView**: Essential for the required reactive WebChat and Dashboard UI.
    *   **Channels**: Provides the robust WebSocket implementation needed for the CLI-to-Gateway protocol.
    *   **Ecosystem**: Aligns with standard Elixir web development, simplifying maintenance and onboarding.
*   **Consequences**:
    *   We will generate a standard `ClawdexWeb.Endpoint` and Router.
    *   Existing Controllers/Plugs will be migrated to Phoenix standard locations.

### 2. Tool Execution "Safe Mode"
*   **Decision**: Implement a strict **Safe Mode** for the `Bash` tool.
*   **Details**:
    *   **Default**: Safe Mode is `true` by default.
    *   **Behavior**: When enabled, ANY execution of the `Bash` tool requires explicit user confirmation via the UI or CLI.
    *   **Output**: Use `Port` to stream output (instead of `System.cmd` waiting for exit) and enforce a strict output byte limit (e.g., 10KB) to prevent context window exhaustion.
*   **Rationale**: The agent operating without a sandbox (Container/VM) is high-risk. Safe Mode prevents accidental destructive commands (`rm -rf`) or run-away processes from damaging the host system/workspace.

### 3. Internal Event Bus via Phoenix.PubSub
*   **Decision**: Use **Phoenix.PubSub** for communication between the Agent Gateway and the Web UI.
*   **Details**:
    *   The Agent Gateway publishes events (tool usage, thoughts, output) to a topic like `"gateway:events:{session_id}"`.
    *   LiveView processes subscribe directly to these topics to stream updates to the browser.
*   **Rationale**:
    *   Avoids the overhead and complexity of opening a loopback WebSocket connection from the backend to itself (which was the initial idea).
    *   Leverages OTP distribution natively if we ever scale to multiple nodes.

### 4. CLI Distribution via Burrito
*   **Decision**: Use **Burrito** to package the CLI client.
*   **Rationale**: Provides a seamless single-binary experience for users on macOS, Linux, and Windows, encapsulating the Erlang runtime.

## Consequences
*   **Dependency Size**: Adding Phoenix increases the release size, but Burrito compression helps mitigate this.
*   **Migration Effort**: Moving the existing `Plug` router to Phoenix requires a dedicated refactoring task.
