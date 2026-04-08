defmodule Jido.Harness.Connection.Framing.NDJSONTest do
  use ExUnit.Case, async: true

  alias Jido.Harness.Connection.Framing.NDJSON

  describe "encode/1" do
    test "encodes map as JSON with trailing newline" do
      result = IO.iodata_to_binary(NDJSON.encode(%{"method" => "initialize"}))
      assert result == ~s({"method":"initialize"}\n)
    end
  end

  describe "decode_buffer/1" do
    test "parses complete single-line JSON" do
      {messages, remaining} = NDJSON.decode_buffer(~s({"id":1,"result":"ok"}\n))
      assert [%{"id" => 1, "result" => "ok"}] = messages
      assert remaining == ""
    end

    test "parses multiple complete lines" do
      buffer = ~s({"id":1}\n{"id":2}\n)
      {messages, remaining} = NDJSON.decode_buffer(buffer)
      assert length(messages) == 2
      assert remaining == ""
    end

    test "buffers incomplete line" do
      buffer = ~s({"id":1}\n{"id":2)
      {messages, remaining} = NDJSON.decode_buffer(buffer)
      assert [%{"id" => 1}] = messages
      assert remaining == ~s({"id":2)
    end

    test "handles empty buffer" do
      {messages, remaining} = NDJSON.decode_buffer("")
      assert messages == []
      assert remaining == ""
    end

    test "skips non-JSON lines" do
      buffer = "not json\n{\"id\":1}\n"
      {messages, _remaining} = NDJSON.decode_buffer(buffer)
      assert [%{"id" => 1}] = messages
    end

    test "skips empty lines" do
      buffer = "\n\n{\"id\":1}\n\n"
      {messages, _remaining} = NDJSON.decode_buffer(buffer)
      assert [%{"id" => 1}] = messages
    end
  end

  describe "port_opts/0" do
    test "returns binary stream options" do
      opts = NDJSON.port_opts()
      assert :binary in opts
      assert :exit_status in opts
      assert :stream in opts
    end
  end
end
