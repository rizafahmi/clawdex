defmodule Clawdex.Session.RegistryTest do
  use ExUnit.Case, async: true

  alias Clawdex.Session.SessionRegistry

  describe "get_or_start/1" do
    test "starts a new session if one doesn't exist" do
      key = "test_key_#{System.unique_integer()}"
      assert :not_found == SessionRegistry.lookup(key)

      {:ok, pid} = SessionRegistry.get_or_start(key)
      assert is_pid(pid)
      assert Process.alive?(pid)

      assert {:ok, ^pid} = SessionRegistry.lookup(key)
    end

    test "returns existing session if it already exists" do
      key = "test_key_#{System.unique_integer()}"
      {:ok, pid1} = SessionRegistry.get_or_start(key)
      {:ok, pid2} = SessionRegistry.get_or_start(key)

      assert pid1 == pid2
    end
  end

  describe "stop/1" do
    test "stops a running session" do
      key = "test_key_#{System.unique_integer()}"
      {:ok, pid} = SessionRegistry.get_or_start(key)

      assert :ok = SessionRegistry.stop(key)

      # Wait for termination and registry cleanup
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000

      # Registry update is async, give it a moment
      Process.sleep(10)
      assert :not_found == SessionRegistry.lookup(key)
    end

    test "returns :ok if session not found" do
      key = "non_existent_key"
      assert :ok == SessionRegistry.stop(key)
    end
  end

  describe "list/0" do
    test "lists active session keys" do
      initial_count = length(SessionRegistry.list())

      key1 = "list_key_1_#{System.unique_integer()}"
      key2 = "list_key_2_#{System.unique_integer()}"

      SessionRegistry.get_or_start(key1)
      SessionRegistry.get_or_start(key2)

      keys = SessionRegistry.list()
      assert length(keys) >= initial_count + 2
      assert key1 in keys
      assert key2 in keys
    end
  end
end
