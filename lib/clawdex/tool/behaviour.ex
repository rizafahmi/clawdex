defmodule Clawdex.Tool.Behaviour do
  @moduledoc false

  @type tool_input :: map()
  @type tool_result :: %{output: String.t(), error: String.t() | nil, exit_code: integer() | nil}

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters_schema() :: map()
  @callback execute(tool_input(), context :: map()) :: {:ok, tool_result()} | {:error, term()}
end
