defmodule Clawdex.Session.Store.SessionRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "sessions" do
    field(:session_key, :string)
    field(:channel, :string)
    field(:chat_id, :string)
    field(:model_override, :string)
    field(:message_count, :integer, default: 0)

    has_many(:messages, Clawdex.Session.Store.MessageRecord, foreign_key: :session_id)

    timestamps()
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:session_key, :channel, :chat_id, :model_override, :message_count])
    |> validate_required([:session_key, :channel, :chat_id])
    |> unique_constraint(:session_key)
  end
end
