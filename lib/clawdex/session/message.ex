defmodule Clawdex.Session.Message do
  @moduledoc false

  defstruct [:role, :content, :timestamp]

  @type t :: %__MODULE__{
          role: :user | :assistant,
          content: String.t(),
          timestamp: DateTime.t()
        }

  @spec new(role :: :user | :assistant, content :: String.t()) :: t()
  def new(role, content) when role in [:user, :assistant] do
    %__MODULE__{
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }
  end

  @spec to_api_format(t()) :: %{role: String.t(), content: String.t()}
  def to_api_format(%__MODULE__{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end
end
