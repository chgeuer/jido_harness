defmodule Jido.Harness.Connection do
  @moduledoc """
  Shared GenServer infrastructure for CLI agent connections.

  Handles dual transport (local Port spawning vs external TCP/vsock socket),
  wire framing (NDJSON or LSP), JSON-RPC request/response correlation,
  subscriber management, permission handling, and graceful cleanup.

  ## Usage

  Adapter packages implement `Jido.Harness.Connection.Protocol` and start
  this GenServer with their protocol module:

      Jido.Harness.Connection.start_link(
        protocol: MyAdapter.Protocol,
        cwd: "/repo",
        permission_handler: :auto_approve
      )

  ## Transport Modes

  - **Local**: Spawns CLI via Erlang Port (default when no `:io` option)
  - **Socket**: Accepts a pre-connected `:gen_tcp` socket (pass `io: socket`)
  """

  use GenServer

  require Logger

  defstruct [
    :port,
    :port_pid,
    :io_socket,
    :io_reader,
    :protocol_module,
    :protocol_state,
    buffer: <<>>,
    next_id: 1,
    pending_requests: %{},
    subscribers: %{},
    cli_path: nil,
    cli_args: [],
    cwd: nil,
    permission_handler: :auto_approve
  ]

  @default_timeout to_timeout(minute: 2)

  # -- Public API ---------------------------------------------------------------

  @doc "Start a connection with the given protocol module and options."
  def start_link(opts \\ []) do
    socket = Keyword.get(opts, :io)

    case socket do
      nil ->
        GenServer.start_link(__MODULE__, opts)

      _ ->
        {:ok, pid} = GenServer.start_link(__MODULE__, Keyword.put(opts, :io_mode, true))
        :gen_tcp.controlling_process(socket, pid)
        GenServer.cast(pid, {:accept_socket, socket})
        {:ok, pid}
    end
  end

  @doc "Send a JSON-RPC request and wait for the response."
  def call_rpc(conn, method, params \\ %{}, meta \\ nil, timeout \\ @default_timeout) do
    GenServer.call(conn, {:rpc_call, method, params, meta}, timeout)
  end

  @doc "Send a JSON-RPC notification (no response expected)."
  def cast_rpc(conn, method, params \\ %{}) do
    GenServer.cast(conn, {:rpc_cast, method, params})
  end

  @doc "Subscribe to events for a session. Events sent as `{:connection_event, session_id, event}`."
  def subscribe(conn, session_id) do
    GenServer.call(conn, {:subscribe, session_id, self()})
  end

  @doc "Unsubscribe from session events."
  def unsubscribe(conn, session_id) do
    GenServer.call(conn, {:unsubscribe, session_id, self()})
  end

  @doc "Stop the connection."
  def stop(conn) do
    GenServer.stop(conn, :normal)
  end

  # -- GenServer Callbacks ------------------------------------------------------

  @impl true
  def init(opts) do
    protocol = Keyword.fetch!(opts, :protocol)

    state = %__MODULE__{
      protocol_module: protocol,
      protocol_state: Keyword.get(opts, :protocol_state),
      cwd: Keyword.get(opts, :cwd),
      permission_handler: Keyword.get(opts, :permission_handler, :auto_approve)
    }

    if Keyword.get(opts, :io_mode) do
      {:ok, state}
    else
      {:ok, state, {:continue, {:start_local, opts}}}
    end
  end

  @impl true
  def handle_continue({:start_local, opts}, state) do
    protocol = state.protocol_module
    {cli_path, cli_args} = protocol.cli_command(opts)
    port_opts = protocol.port_opts()

    env =
      Keyword.get(opts, :env, [])
      |> Enum.map(fn {k, v} -> {String.to_charlist(to_string(k)), String.to_charlist(to_string(v))} end)

    cwd = state.cwd || File.cwd!()

    full_port_opts =
      [{:args, cli_args}, {:cd, cwd}, {:env, env} | port_opts]

    port = Port.open({:spawn_executable, cli_path}, full_port_opts)

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end

    new_state = %{state | port: port, port_pid: os_pid, cli_path: cli_path, cli_args: cli_args}

    # Send initialize request
    init_request = protocol.initialize_request(opts)
    send_wire(new_state, init_request)

    {:noreply, new_state}
  end

  # Accept external socket after ownership transfer
  @impl true
  def handle_cast({:accept_socket, socket}, state) do
    new_state = %{state | io_socket: socket}

    # Spawn reader process
    parent = self()

    reader =
      spawn_link(fn ->
        receive do
          :socket_ready -> io_reader_loop(socket, parent)
        after
          10_000 -> :timeout
        end
      end)

    :gen_tcp.controlling_process(socket, reader)
    Kernel.send(reader, :socket_ready)

    new_state = %{new_state | io_reader: reader}

    # Send initialize request
    init_request = state.protocol_module.initialize_request([])
    send_wire(new_state, init_request)

    {:noreply, new_state}
  end

  # Send JSON-RPC notification (no id, no pending)
  @impl true
  def handle_cast({:rpc_cast, method, params}, state) do
    json = %{"jsonrpc" => "2.0", "method" => method, "params" => params}
    send_wire(state, json)
    {:noreply, state}
  end

  # Send JSON-RPC request (with id, store in pending)
  @impl true
  def handle_call({:rpc_call, method, params, meta}, from, state) do
    {id, state} = next_id(state)
    json = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
    send_wire(state, json)
    new_pending = Map.put(state.pending_requests, id, {meta, from})
    {:noreply, %{state | pending_requests: new_pending}}
  end

  def handle_call({:subscribe, session_id, pid}, _from, state) do
    Process.monitor(pid)
    subs = Map.update(state.subscribers, session_id, [pid], fn pids -> [pid | pids] end)
    {:reply, :ok, %{state | subscribers: subs}}
  end

  def handle_call({:unsubscribe, session_id, pid}, _from, state) do
    subs =
      Map.update(state.subscribers, session_id, [], fn pids ->
        Enum.reject(pids, &(&1 == pid))
      end)

    {:reply, :ok, %{state | subscribers: subs}}
  end

  # -- Port Data ---------------------------------------------------------------

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {:noreply, process_data(state, data)}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    broadcast_all(state, {:connection_exit, code})
    fail_pending(state, {:connection_closed, code})
    {:stop, :normal, %{state | port: nil}}
  end

  # -- Socket Data -------------------------------------------------------------

  def handle_info({:io_data, data}, %{io_socket: sock} = state) when not is_nil(sock) do
    {:noreply, process_data(state, data)}
  end

  def handle_info(:io_closed, state) do
    broadcast_all(state, {:connection_exit, 0})
    fail_pending(state, :connection_closed)
    {:stop, :normal, %{state | io_socket: nil}}
  end

  def handle_info({:io_error, reason}, state) do
    Logger.error("[connection] I/O error: #{inspect(reason)}")
    {:stop, {:io_error, reason}, state}
  end

  # -- Subscriber Cleanup ------------------------------------------------------

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    subs =
      Enum.reduce(state.subscribers, %{}, fn {sid, pids}, acc ->
        filtered = Enum.reject(pids, &(&1 == pid))
        if filtered == [], do: acc, else: Map.put(acc, sid, filtered)
      end)

    {:noreply, %{state | subscribers: subs}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- Terminate ---------------------------------------------------------------

  @impl true
  def terminate(_reason, %{port: port}) when not is_nil(port) do
    Port.close(port)
  end

  def terminate(_reason, %{io_socket: sock}) when not is_nil(sock) do
    :gen_tcp.close(sock)
  end

  def terminate(_reason, _state), do: :ok

  # -- Internal ----------------------------------------------------------------

  defp process_data(state, data) do
    buffer = state.buffer <> data
    protocol = state.protocol_module
    {messages, remaining} = protocol.decode_buffer(buffer)

    state = %{state | buffer: remaining}

    Enum.reduce(messages, state, fn msg, st ->
      handle_jsonrpc(st, msg)
    end)
  end

  # JSON-RPC response (has id + result)
  defp handle_jsonrpc(state, %{"id" => id, "result" => _result} = msg) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        Logger.warning("[connection] Response for unknown request id=#{id}")
        state

      {{meta, from}, remaining} ->
        state = %{state | pending_requests: remaining}

        case state.protocol_module.handle_response(msg, meta) do
          {:reply, value} ->
            GenServer.reply(from, {:ok, value})
            state

          {:broadcast, session_id, event} ->
            GenServer.reply(from, :ok)
            broadcast(state, session_id, event)
            state

          :ignore ->
            GenServer.reply(from, :ok)
            state
        end
    end
  end

  # JSON-RPC error response (has id + error)
  defp handle_jsonrpc(state, %{"id" => id, "error" => error}) do
    case Map.pop(state.pending_requests, id) do
      {nil, _} ->
        state

      {{_meta, from}, remaining} ->
        GenServer.reply(from, {:error, error})
        %{state | pending_requests: remaining}
    end
  end

  # Server notification (no id, has method)
  defp handle_jsonrpc(state, %{"method" => _method} = msg) when not is_map_key(msg, "id") do
    case state.protocol_module.handle_notification(msg) do
      {:broadcast, session_id, event} ->
        broadcast(state, session_id, event)
        state

      {:broadcast_all, event} ->
        broadcast_all(state, event)
        state

      :ignore ->
        state
    end
  end

  # Server request (has id + method, expects response)
  defp handle_jsonrpc(state, %{"id" => _id, "method" => _method} = msg) do
    case state.protocol_module.handle_server_request(msg, state.permission_handler) do
      {:reply_json, response} ->
        send_wire(state, response)
        state

      :ignore ->
        state
    end
  end

  defp handle_jsonrpc(state, _msg), do: state

  # -- Wire I/O ----------------------------------------------------------------

  defp send_wire(%{io_socket: sock}, json) when not is_nil(sock) do
    # For socket mode, we encode manually since protocol.encode might not be loaded
    data = Jason.encode!(json) <> "\n"
    :gen_tcp.send(sock, data)
  end

  defp send_wire(%{port: port, protocol_module: protocol}, json) when not is_nil(port) do
    Port.command(port, IO.iodata_to_binary(protocol.encode(json)))
  end

  defp send_wire(_, _), do: :ok

  # -- Socket Reader -----------------------------------------------------------

  defp io_reader_loop(socket, parent) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        Kernel.send(parent, {:io_data, data})
        io_reader_loop(socket, parent)

      {:error, :timeout} ->
        io_reader_loop(socket, parent)

      {:error, :closed} ->
        Kernel.send(parent, :io_closed)

      {:error, reason} ->
        Kernel.send(parent, {:io_error, reason})
    end
  end

  # -- Helpers -----------------------------------------------------------------

  defp next_id(state) do
    {state.next_id, %{state | next_id: state.next_id + 1}}
  end

  defp broadcast(state, session_id, event) do
    pids = Map.get(state.subscribers, session_id, []) ++ Map.get(state.subscribers, :all, [])

    for pid <- pids do
      Kernel.send(pid, {:connection_event, session_id, event})
    end
  end

  defp broadcast_all(state, event) do
    for {_sid, pids} <- state.subscribers, pid <- pids do
      Kernel.send(pid, {:connection_event, :all, event})
    end
  end

  defp fail_pending(state, reason) do
    for {_id, {_meta, from}} <- state.pending_requests do
      GenServer.reply(from, {:error, reason})
    end
  end
end
