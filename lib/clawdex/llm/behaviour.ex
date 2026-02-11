defmodule Clawdex.LLM.Behaviour do
  @moduledoc false

  @type message :: %{String.t() => String.t()}
  @type opts :: [model: String.t(), system: String.t(), max_tokens: integer()]

  @callback chat(messages :: [message()], opts :: opts()) ::
              {:ok, String.t()} | {:error, term()}
end
