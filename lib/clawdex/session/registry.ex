defmodule Clawdex.Session.SessionRegistry do
  @moduledoc false

  @spec get_or_start(String.t()) :: {:ok, pid()}
  def get_or_start(session_key) do
    case lookup(session_key) do
      {:ok, pid} ->
        {:ok, pid}

      :not_found ->
        case DynamicSupervisor.start_child(
               Clawdex.Session.DynamicSupervisor,
               {Clawdex.Session, session_key}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end
    end
  end

  @spec lookup(String.t()) :: {:ok, pid()} | :not_found
  def lookup(session_key) do
    case Registry.lookup(Clawdex.Session.Registry, session_key) do
      [{pid, _}] -> {:ok, pid}
      [] -> :not_found
    end
  end

  @spec stop(String.t()) :: :ok
  def stop(session_key) do
    case lookup(session_key) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(Clawdex.Session.DynamicSupervisor, pid)
      :not_found -> :ok
    end
  end

  @spec list() :: [String.t()]
  def list do
    Clawdex.Session.Registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
  end
end
