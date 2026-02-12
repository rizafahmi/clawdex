defmodule Clawdex.Tool.Registry do
  @moduledoc false

  @tools [
    Clawdex.Tool.Bash,
    Clawdex.Tool.Read,
    Clawdex.Tool.Write,
    Clawdex.Tool.Edit
  ]

  @spec list() :: [module()]
  def list do
    @tools
  end

  @spec list(map()) :: [module()]
  def list(policy) do
    allow = Map.get(policy, :allow, Enum.map(@tools, & &1.name()))
    deny = Map.get(policy, :deny, [])

    Enum.filter(@tools, fn tool ->
      tool.name() in allow and tool.name() not in deny
    end)
  end

  @spec get(String.t()) :: {:ok, module()} | :not_found
  def get(name) do
    case Enum.find(@tools, fn tool -> tool.name() == name end) do
      nil -> :not_found
      tool -> {:ok, tool}
    end
  end

  @spec schemas() :: [map()]
  def schemas, do: schemas(%{})

  @spec schemas(map()) :: [map()]
  def schemas(policy) do
    policy
    |> list()
    |> Enum.map(fn tool ->
      %{
        "name" => tool.name(),
        "description" => tool.description(),
        "input_schema" => tool.parameters_schema()
      }
    end)
  end
end
