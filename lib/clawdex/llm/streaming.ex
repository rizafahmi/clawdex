defmodule Clawdex.LLM.Streaming do
  @moduledoc false

  @type chunk :: %{content: String.t(), done: boolean()}
  @type callback :: (chunk() -> :ok)

  @update_interval 500
  @min_chars 100

  defstruct [
    :chat_id,
    :message_id,
    :channel_module,
    :timer_ref,
    buffer: "",
    last_sent: "",
    last_sent_at: 0
  ]

  @spec stream_to_channel(Enumerable.t(), term(), module()) :: {:ok, String.t()} | {:error, term()}
  def stream_to_channel(chunks, chat_id, channel_module) do
    state = %__MODULE__{
      chat_id: chat_id,
      channel_module: channel_module
    }

    Enum.reduce_while(chunks, state, fn
      %{content: content, done: false}, acc ->
        acc = %{acc | buffer: acc.buffer <> content}
        acc = maybe_send_update(acc)
        {:cont, acc}

      %{content: content, done: true}, acc ->
        acc = %{acc | buffer: acc.buffer <> content}
        {:halt, acc}
    end)
    |> case do
      %__MODULE__{} = final ->
        cancel_timer(final.timer_ref)
        send_final(final)
        {:ok, final.buffer}

      {:error, _} = error ->
        error
    end
  end

  defp maybe_send_update(%{message_id: nil} = state) do
    if String.length(state.buffer) >= @min_chars do
      case state.channel_module.send_reply(state.chat_id, state.buffer <> " ▍") do
        {:ok, message_id} ->
          %{state | message_id: message_id, last_sent: state.buffer, last_sent_at: now_ms()}

        {:error, _} ->
          state
      end
    else
      state
    end
  end

  defp maybe_send_update(state) do
    chars_diff = String.length(state.buffer) - String.length(state.last_sent)
    time_diff = now_ms() - state.last_sent_at

    if chars_diff >= @min_chars or time_diff >= @update_interval do
      do_edit(state)
    else
      schedule_update(state)
    end
  end

  defp do_edit(state) do
    cancel_timer(state.timer_ref)

    case state.channel_module.edit_reply(state.chat_id, state.message_id, state.buffer <> " ▍") do
      :ok ->
        %{state | last_sent: state.buffer, last_sent_at: now_ms(), timer_ref: nil}

      {:error, _} ->
        state
    end
  end

  defp send_final(%{message_id: nil} = state) do
    state.channel_module.send_reply(state.chat_id, state.buffer)
  end

  defp send_final(state) do
    state.channel_module.edit_reply(state.chat_id, state.message_id, state.buffer)
  end

  defp schedule_update(%{timer_ref: nil} = state) do
    ref = Process.send_after(self(), {:stream_update, state.chat_id}, @update_interval)
    %{state | timer_ref: ref}
  end

  defp schedule_update(state), do: state

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp now_ms, do: System.monotonic_time(:millisecond)
end
