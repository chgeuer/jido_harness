defmodule Jido.Harness.Connection.Protocol do
  @moduledoc """
  Behaviour for CLI agent connection protocols.

  Implementations define how to encode/decode wire messages, which CLI to spawn,
  how to handle JSON-RPC responses and notifications, and how to handle
  permission requests from the agent.

  Two framing implementations are provided:
  - `Jido.Harness.Connection.Framing.NDJSON` — newline-delimited JSON (ACP)
  - `Jido.Harness.Connection.Framing.LSP` — Content-Length framed JSON (CLI Server)
  """

  @doc "Return CLI executable path and args for local spawning."
  @callback cli_command(opts :: keyword()) :: {path :: String.t(), args :: [String.t()]}

  @doc "Encode a map into wire format (returns iodata)."
  @callback encode(json :: map()) :: iodata()

  @doc "Parse buffered data into {[decoded_messages], remaining_buffer}."
  @callback decode_buffer(buffer :: binary()) :: {[map()], binary()}

  @doc "Build the initialization request to send after connection."
  @callback initialize_request(opts :: keyword()) :: map() | nil

  @doc """
  Handle a decoded JSON-RPC response (has an `id` field).

  Return:
  - `{:reply, reply_value}` — reply to the pending GenServer caller
  - `{:broadcast, session_id, event}` — broadcast to subscribers
  - `:ignore` — drop the message
  """
  @callback handle_response(response :: map(), request_meta :: term()) ::
              {:reply, reply_value :: term()}
            | {:broadcast, session_id :: String.t(), event :: term()}
            | :ignore

  @doc """
  Handle a server-initiated notification (no `id` field).

  Return:
  - `{:broadcast, session_id, event}` — broadcast to subscribers
  - `{:broadcast_all, event}` — broadcast to all subscribers
  - `:ignore` — drop the message
  """
  @callback handle_notification(notification :: map()) ::
              {:broadcast, session_id :: String.t(), event :: term()}
            | {:broadcast_all, event :: term()}
            | :ignore

  @doc """
  Handle a server-initiated request (has `id` and `method`, expects a response).

  Return:
  - `{:reply_json, response_map}` — send JSON response back to the agent
  - `:ignore` — drop the message
  """
  @callback handle_server_request(request :: map(), permission_handler :: term()) ::
              {:reply_json, response :: map()}
            | :ignore

  @doc "Port.open options for local spawning."
  @callback port_opts() :: keyword()

  @doc """
  Optional hook invoked after connection established and init request sent.
  Useful for health checks or handshakes. Default is no-op.
  """
  @callback after_connect(state :: term()) :: {:ok, term()} | {:error, term()}

  @optional_callbacks [after_connect: 1]
end
