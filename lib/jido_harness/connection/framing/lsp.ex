defmodule Jido.Harness.Connection.Framing.LSP do
  @moduledoc """
  Content-Length framed JSON for CLI Server Protocol.

  Each message is prefixed with `Content-Length: N\\r\\n\\r\\n` followed by
  exactly N bytes of JSON.
  """

  @doc "Encode a map with Content-Length framing."
  @spec encode(map()) :: iodata()
  def encode(json) when is_map(json) do
    body = Jason.encode!(json)
    ["Content-Length: ", Integer.to_string(byte_size(body)), "\r\n\r\n", body]
  end

  @doc "Extract complete LSP-framed messages from buffer."
  @spec decode_buffer(binary()) :: {[map()], binary()}
  def decode_buffer(buffer) when is_binary(buffer) do
    extract_messages(buffer, [])
  end

  @doc "Port.open options for LSP — binary stream mode."
  @spec port_opts() :: keyword()
  def port_opts, do: [:binary, :exit_status, :use_stdio, :stream]

  defp extract_messages(buffer, acc) do
    case extract_one_message(buffer) do
      {:ok, msg, rest} -> extract_messages(rest, [msg | acc])
      :incomplete -> {Enum.reverse(acc), buffer}
    end
  end

  defp extract_one_message(buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [_incomplete] ->
        :incomplete

      [headers, rest] ->
        case parse_content_length(headers) do
          {:ok, length} when byte_size(rest) >= length ->
            <<body::binary-size(^length), remaining::binary>> = rest

            case Jason.decode(body) do
              {:ok, msg} -> {:ok, msg, remaining}
              {:error, _} -> {:ok, %{"_parse_error" => true}, remaining}
            end

          _ ->
            :incomplete
        end
    end
  end

  defp parse_content_length(headers) do
    headers
    |> String.split("\r\n")
    |> Enum.find_value(:error, fn line ->
      case String.split(line, ":", parts: 2) do
        ["Content-Length", value] ->
          case Integer.parse(String.trim(value)) do
            {n, _} -> {:ok, n}
            :error -> nil
          end

        _ ->
          nil
      end
    end)
  end
end
