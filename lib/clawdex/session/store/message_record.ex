defmodule Clawdex.Session.Store.MessageRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "messages" do
    belongs_to(:session, Clawdex.Session.Store.SessionRecord)

    field(:role, :string)
    field(:content, :string)
    field(:token_count, :integer)

    timestamps(updated_at: false)
  end

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:session_id, :role, :content, :token_count])
    |> validate_required([:session_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
    |> foreign_key_constraint(:session_id)
  end
end
