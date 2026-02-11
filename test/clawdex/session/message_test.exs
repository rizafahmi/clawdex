defmodule Clawdex.Session.MessageTest do
  use ExUnit.Case, async: true
  alias Clawdex.Session.Message

  describe "new/2" do
    test "creates a user message with timestamp" do
      msg = Message.new(:user, "Hello")
      assert msg.role == :user
      assert msg.content == "Hello"
      assert %DateTime{} = msg.timestamp
    end

    test "creates an assistant message" do
      msg = Message.new(:assistant, "Hi there")
      assert msg.role == :assistant
      assert msg.content == "Hi there"
    end

    test "raises function clause error for invalid role" do
      assert_raise FunctionClauseError, fn ->
        Message.new(:invalid, "test")
      end
    end
  end

  describe "to_api_format/1" do
    test "converts user message to map" do
      msg = Message.new(:user, "Hello")
      assert Message.to_api_format(msg) == %{"role" => "user", "content" => "Hello"}
    end

    test "converts assistant message to map" do
      msg = Message.new(:assistant, "Hi")
      assert Message.to_api_format(msg) == %{"role" => "assistant", "content" => "Hi"}
    end
  end
end
