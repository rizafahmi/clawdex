defmodule Clawdex.Session.Store do
  @moduledoc false

  import Ecto.Query

  alias Clawdex.Repo
  alias Clawdex.Session.Store.{SessionRecord, MessageRecord}

  @spec find_or_create_session(String.t()) :: {:ok, SessionRecord.t()} | {:error, term()}
  def find_or_create_session(session_key) do
    case Repo.get_by(SessionRecord, session_key: session_key) do
      nil ->
        {channel, chat_id} = parse_session_key(session_key)

        %SessionRecord{}
        |> SessionRecord.changeset(%{
          session_key: session_key,
          channel: channel,
          chat_id: chat_id
        })
        |> Repo.insert()

      record ->
        {:ok, record}
    end
  end

  @spec load_messages(integer()) :: [MessageRecord.t()]
  def load_messages(session_id) do
    MessageRecord
    |> where([m], m.session_id == ^session_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @spec append_message(integer(), map()) :: {:ok, MessageRecord.t()} | {:error, term()}
  def append_message(session_id, attrs) do
    token_count = estimate_tokens(attrs.content)

    %MessageRecord{}
    |> MessageRecord.changeset(Map.merge(attrs, %{session_id: session_id, token_count: token_count}))
    |> Repo.insert()
    |> tap(fn
      {:ok, _} -> update_message_count(session_id)
      _ -> :ok
    end)
  end

  @spec clear_messages(integer()) :: :ok
  def clear_messages(session_id) do
    MessageRecord
    |> where([m], m.session_id == ^session_id)
    |> Repo.delete_all()

    SessionRecord
    |> where([s], s.id == ^session_id)
    |> Repo.update_all(set: [message_count: 0])

    :ok
  end

  @spec set_model_override(integer(), String.t() | nil) :: :ok
  def set_model_override(session_id, model) do
    SessionRecord
    |> where([s], s.id == ^session_id)
    |> Repo.update_all(set: [model_override: model])

    :ok
  end

  @spec get_session_by_key(String.t()) :: SessionRecord.t() | nil
  def get_session_by_key(session_key) do
    Repo.get_by(SessionRecord, session_key: session_key)
  end

  defp update_message_count(session_id) do
    count =
      MessageRecord
      |> where([m], m.session_id == ^session_id)
      |> Repo.aggregate(:count)

    SessionRecord
    |> where([s], s.id == ^session_id)
    |> Repo.update_all(set: [message_count: count])
  end

  defp parse_session_key(key) do
    case String.split(key, ":", parts: 2) do
      [channel, chat_id] -> {channel, chat_id}
      _ -> {"unknown", key}
    end
  end

  defp estimate_tokens(content) when is_binary(content) do
    div(String.length(content), 4)
  end

  defp estimate_tokens(_), do: 0
end
