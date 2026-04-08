defmodule Jido.Harness.Connection.Framing.LSPTest do
  use ExUnit.Case, async: true

  alias Jido.Harness.Connection.Framing.LSP

  describe "encode/1" do
    test "encodes with Content-Length header" do
      result = IO.iodata_to_binary(LSP.encode(%{"id" => 1}))
      body = Jason.encode!(%{"id" => 1})
      expected = "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"
      assert result == expected
    end
  end

  describe "decode_buffer/1" do
    test "parses single complete message" do
      body = Jason.encode!(%{"id" => 1, "result" => "ok"})
      buffer = "Content-Length: #{byte_size(body)}\r\n\r\n#{body}"
      {messages, remaining} = LSP.decode_buffer(buffer)
      assert [%{"id" => 1, "result" => "ok"}] = messages
      assert remaining == ""
    end

    test "parses multiple complete messages" do
      body1 = Jason.encode!(%{"id" => 1})
      body2 = Jason.encode!(%{"id" => 2})
      buffer = "Content-Length: #{byte_size(body1)}\r\n\r\n#{body1}Content-Length: #{byte_size(body2)}\r\n\r\n#{body2}"
      {messages, remaining} = LSP.decode_buffer(buffer)
      assert length(messages) == 2
      assert remaining == ""
    end

    test "buffers incomplete header" do
      {messages, remaining} = LSP.decode_buffer("Content-Leng")
      assert messages == []
      assert remaining == "Content-Leng"
    end

    test "buffers incomplete body" do
      body = Jason.encode!(%{"id" => 1, "data" => "long"})
      buffer = "Content-Length: #{byte_size(body)}\r\n\r\n#{String.slice(body, 0..3)}"
      {messages, remaining} = LSP.decode_buffer(buffer)
      assert messages == []
      assert remaining == buffer
    end

    test "handles empty buffer" do
      {messages, remaining} = LSP.decode_buffer("")
      assert messages == []
      assert remaining == ""
    end

    test "round-trips encode then decode" do
      original = %{"jsonrpc" => "2.0", "id" => 42, "method" => "test"}
      encoded = IO.iodata_to_binary(LSP.encode(original))
      {[decoded], ""} = LSP.decode_buffer(encoded)
      assert decoded == original
    end
  end

  describe "port_opts/0" do
    test "returns binary stream options" do
      opts = LSP.port_opts()
      assert :binary in opts
      assert :exit_status in opts
      assert :stream in opts
    end
  end
end
