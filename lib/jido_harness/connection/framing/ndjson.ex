defmodule Jido.Harness.Connection.Framing.NDJSON do
  @moduledoc """
  Newline-delimited JSON framing for ACP (Agent Communication Protocol).

  Each message is a single JSON object terminated by `\\n`.
  """

  @doc "Encode a map as a JSON line."
  @spec encode(map()) :: iodata()
  def encode(json) when is_map(json) do
    [Jason.encode!(json), "\n"]
  end

  @doc "Split buffer on newlines, parse complete JSON lines."
  @spec decode_buffer(binary()) :: {[map()], binary()}
  def decode_buffer(buffer) when is_binary(buffer) do
    {lines, remaining} = split_lines(buffer)

    messages =
      Enum.flat_map(lines, fn line ->
        line = String.trim(line)

        if line == "" do
          []
        else
          case Jason.decode(line) do
            {:ok, msg} -> [msg]
            {:error, _} -> []
          end
        end
      end)

    {messages, remaining}
  end

  @doc "Port.open options for NDJSON — binary stream mode."
  @spec port_opts() :: keyword()
  def port_opts, do: [:binary, :exit_status, :use_stdio, :stream]

  defp split_lines(data) do
    case :binary.split(data, "\n", [:global]) do
      [single] -> {[], single}
      parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
    end
  end
end
