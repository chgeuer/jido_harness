defmodule Jido.Harness.Event.CanonicalTest do
  use ExUnit.Case, async: true

  alias Jido.Harness.Event
  alias Jido.Harness.Event.Canonical

  describe "session lifecycle" do
    test "session_started builds valid event" do
      event = Canonical.session_started(:claude, "sess-1", model: "sonnet", cwd: "/repo")
      assert %Event{type: :session_started, provider: :claude, session_id: "sess-1"} = event
      assert event.payload["model"] == "sonnet"
      assert event.payload["cwd"] == "/repo"
      assert event.payload["session_id"] == "sess-1"
      assert is_binary(event.timestamp)
    end

    test "session_completed builds valid event" do
      event = Canonical.session_completed(:gemini, "sess-2", stop_reason: "end_turn", duration_ms: 1500)
      assert %Event{type: :session_completed, provider: :gemini} = event
      assert event.payload["stop_reason"] == "end_turn"
      assert event.payload["duration_ms"] == 1500
    end

    test "session_failed builds valid event" do
      event = Canonical.session_failed(:codex, "sess-3", "API timeout", code: "timeout")
      assert %Event{type: :session_failed} = event
      assert event.payload["error"] == "API timeout"
      assert event.payload["code"] == "timeout"
    end

    test "session_cancelled builds valid event" do
      event = Canonical.session_cancelled(:claude, "sess-4", reason: "user_request")
      assert %Event{type: :session_cancelled} = event
      assert event.payload["reason"] == "user_request"
    end
  end

  describe "content streaming" do
    test "text_delta builds valid event" do
      event = Canonical.text_delta(:claude, "sess-1", "Hello ")
      assert %Event{type: :output_text_delta} = event
      assert event.payload["text"] == "Hello "
    end

    test "text_final builds valid event" do
      event = Canonical.text_final(:gemini, "sess-1", "Complete message")
      assert %Event{type: :output_text_final} = event
      assert event.payload["text"] == "Complete message"
    end

    test "thinking_delta builds valid event" do
      event = Canonical.thinking_delta(:claude, "sess-1", "Let me think...")
      assert %Event{type: :thinking_delta} = event
      assert event.payload["text"] == "Let me think..."
      assert event.payload["redacted"] == false
      refute Map.has_key?(event.payload, "signature")
    end

    test "thinking_delta with redacted flag" do
      event = Canonical.thinking_delta(:claude, "sess-1", "", redacted: true, signature: "sig123")
      assert event.payload["redacted"] == true
      assert event.payload["signature"] == "sig123"
    end
  end

  describe "tool execution" do
    test "tool_use_start builds valid event" do
      event = Canonical.tool_use_start(:claude, "sess-1", "Read", "call-42", %{"path" => "/foo"})
      assert %Event{type: :tool_use_start} = event
      assert event.payload["name"] == "Read"
      assert event.payload["call_id"] == "call-42"
      assert event.payload["input"] == %{"path" => "/foo"}
    end

    test "tool_use_start with empty input" do
      event = Canonical.tool_use_start(:codex, "sess-1", "Bash", "call-1")
      assert event.payload["input"] == %{}
    end

    test "tool_use_end builds valid event" do
      event = Canonical.tool_use_end(:claude, "sess-1", "call-42", output: "file contents", is_error: false)
      assert %Event{type: :tool_use_end} = event
      assert event.payload["call_id"] == "call-42"
      assert event.payload["output"] == "file contents"
      assert event.payload["is_error"] == false
    end

    test "tool_use_end with error" do
      event = Canonical.tool_use_end(:codex, "sess-1", "call-99", output: "Permission denied", is_error: true)
      assert event.payload["is_error"] == true
    end
  end

  describe "turn boundaries" do
    test "turn_start builds valid event" do
      event = Canonical.turn_start(:codex, "sess-1")
      assert %Event{type: :turn_start, provider: :codex, session_id: "sess-1"} = event
    end

    test "turn_end builds valid event" do
      event = Canonical.turn_end(:claude, "sess-1")
      assert %Event{type: :turn_end, provider: :claude} = event
    end
  end

  describe "user interaction" do
    test "user_message builds valid event" do
      event = Canonical.user_message(:gemini, "sess-1", "Fix the bug")
      assert %Event{type: :user_message} = event
      assert event.payload["text"] == "Fix the bug"
    end

    test "ask_user builds valid event" do
      event = Canonical.ask_user(:codex, "sess-1",
        request_id: "req-1",
        questions: [%{"text" => "Continue?", "type" => "confirm"}])
      assert %Event{type: :ask_user} = event
      assert event.payload["request_id"] == "req-1"
      assert length(event.payload["questions"]) == 1
    end
  end

  describe "file operations" do
    test "file_change builds valid event" do
      event = Canonical.file_change(:codex, "sess-1", "src/app.ex", "modify", content: "new code")
      assert %Event{type: :file_change} = event
      assert event.payload["path"] == "src/app.ex"
      assert event.payload["action"] == "modify"
      assert event.payload["content"] == "new code"
    end
  end

  describe "escape hatch" do
    test "provider_event builds valid event" do
      event = Canonical.provider_event(:codex, "sess-1", "rate_limits_updated",
        %{"requests_remaining" => 42})
      assert %Event{type: :provider_event} = event
      assert event.payload["event_type"] == "rate_limits_updated"
      assert event.payload["provider"] == "codex"
      assert event.payload["requests_remaining"] == 42
    end
  end

  describe "common options" do
    test "raw option passes through" do
      raw = %{some: :struct}
      event = Canonical.text_delta(:claude, "sess-1", "hi", raw: raw)
      assert event.raw == raw
    end

    test "timestamp option overrides auto-generated" do
      ts = "2026-01-01T00:00:00Z"
      event = Canonical.text_delta(:claude, "sess-1", "hi", timestamp: ts)
      assert event.timestamp == ts
    end

    test "payload option merges extra fields" do
      event = Canonical.text_delta(:claude, "sess-1", "hi", payload: %{"custom" => true})
      assert event.payload["text"] == "hi"
      assert event.payload["custom"] == true
    end

    test "nil values are stripped from payload" do
      event = Canonical.session_started(:claude, "sess-1")
      refute Map.has_key?(event.payload, "model")
      refute Map.has_key?(event.payload, "cwd")
    end
  end
end
