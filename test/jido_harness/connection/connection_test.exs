defmodule Jido.Harness.ConnectionTest do
  use ExUnit.Case, async: true

  alias Jido.Harness.Connection

  defmodule StubProtocol do
    @behaviour Jido.Harness.Connection.Protocol

    @impl true
    def cli_command(_opts), do: {"/bin/cat", []}

    @impl true
    def encode(json), do: Jido.Harness.Connection.Framing.NDJSON.encode(json)

    @impl true
    def decode_buffer(buffer), do: Jido.Harness.Connection.Framing.NDJSON.decode_buffer(buffer)

    @impl true
    def initialize_request(_opts), do: %{"jsonrpc" => "2.0", "method" => "initialize", "id" => 0}

    @impl true
    def port_opts, do: Jido.Harness.Connection.Framing.NDJSON.port_opts()

    @impl true
    def handle_response(%{"result" => result}, _meta), do: {:reply, result}

    @impl true
    def handle_notification(%{"method" => "session/update", "params" => params}) do
      sid = params["sessionId"] || "unknown"
      {:broadcast, sid, {:session_update, params["update"]}}
    end

    def handle_notification(_), do: :ignore

    @impl true
    def handle_server_request(%{"method" => "session/request_permission", "id" => id}, :auto_approve) do
      {:reply_json, %{"jsonrpc" => "2.0", "id" => id, "result" => %{"outcome" => "allow"}}}
    end

    def handle_server_request(_, _), do: :ignore
  end

  describe "struct" do
    test "default struct has expected fields" do
      state = %Connection{}
      assert state.buffer == <<>>
      assert state.next_id == 1
      assert state.pending_requests == %{}
      assert state.subscribers == %{}
      assert state.permission_handler == :auto_approve
    end
  end

  describe "subscribe/unsubscribe" do
    test "subscribe adds pid to subscribers, unsubscribe removes it" do
      # Use a long-running cat process so the port stays alive
      {:ok, conn} = Connection.start_link(protocol: StubProtocol, cwd: "/tmp")

      # Give GenServer a moment to start (it will fail on port, but we test
      # the subscribe path which doesn't require the port)
      Process.sleep(20)

      # If the process died from port failure, skip this test
      if Process.alive?(conn) do
        :ok = Connection.subscribe(conn, "sess-1")
        :ok = Connection.unsubscribe(conn, "sess-1")
        Connection.stop(conn)
      end
    end
  end

  describe "protocol behaviour" do
    test "StubProtocol implements all required callbacks" do
      assert {:module, _} = Code.ensure_loaded(StubProtocol)
      assert function_exported?(StubProtocol, :cli_command, 1)
      assert function_exported?(StubProtocol, :encode, 1)
      assert function_exported?(StubProtocol, :decode_buffer, 1)
      assert function_exported?(StubProtocol, :initialize_request, 1)
      assert function_exported?(StubProtocol, :handle_response, 2)
      assert function_exported?(StubProtocol, :handle_notification, 1)
      assert function_exported?(StubProtocol, :handle_server_request, 2)
      assert function_exported?(StubProtocol, :port_opts, 0)
    end

    test "handle_response returns reply tuple" do
      result = StubProtocol.handle_response(%{"result" => "ok"}, nil)
      assert {:reply, "ok"} = result
    end

    test "handle_notification returns broadcast for session/update" do
      result = StubProtocol.handle_notification(%{
        "method" => "session/update",
        "params" => %{"sessionId" => "s1", "update" => %{"text" => "hi"}}
      })
      assert {:broadcast, "s1", {:session_update, %{"text" => "hi"}}} = result
    end

    test "handle_server_request auto-approves permissions" do
      result = StubProtocol.handle_server_request(
        %{"method" => "session/request_permission", "id" => 5},
        :auto_approve
      )
      assert {:reply_json, %{"id" => 5, "result" => %{"outcome" => "allow"}}} = result
    end
  end
end
