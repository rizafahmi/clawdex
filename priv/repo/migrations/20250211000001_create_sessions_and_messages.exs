defmodule Clawdex.Repo.Migrations.CreateSessionsAndMessages do
  use Ecto.Migration

  def change do
    create table(:sessions) do
      add :session_key, :string, null: false
      add :channel, :string, null: false
      add :chat_id, :string, null: false
      add :model_override, :string
      add :message_count, :integer, default: 0

      timestamps()
    end

    create unique_index(:sessions, [:session_key])

    create table(:messages) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :token_count, :integer

      timestamps(updated_at: false)
    end

    create index(:messages, [:session_id])
  end
end
