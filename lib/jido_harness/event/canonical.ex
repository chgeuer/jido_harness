defmodule Jido.Harness.Event.Canonical do
  @moduledoc """
  Builder functions for canonical Harness event types.

  Every adapter stream MUST:
  1. Start with exactly one `:session_started` event
  2. End with exactly one of `:session_completed` | `:session_failed` | `:session_cancelled`
  3. Emit `:usage` before the terminal event (if `usage?: true` capability)

  ## Canonical Event Types

  | Type                | Category         | Description                                    |
  |---------------------|------------------|------------------------------------------------|
  | `:session_started`  | Session          | Session initialized                            |
  | `:session_completed`| Session          | Session ended successfully                     |
  | `:session_failed`   | Session          | Session ended with error                       |
  | `:session_cancelled`| Session          | Session cancelled by user/system               |
  | `:output_text_delta`| Content          | Incremental text chunk (consumer accumulates)  |
  | `:output_text_final`| Content          | Final complete text for a content block        |
  | `:thinking_delta`   | Content          | Extended thinking / reasoning chunk            |
  | `:tool_use_start`   | Tool Execution   | Tool invocation started                        |
  | `:tool_use_end`     | Tool Execution   | Tool invocation completed                      |
  | `:turn_start`       | Turn Boundary    | New agentic turn began                         |
  | `:turn_end`         | Turn Boundary    | Agentic turn completed                         |
  | `:user_message`     | User Interaction | User message echoed                            |
  | `:ask_user`         | User Interaction | Agent requests user input                      |
  | `:file_change`      | File Operations  | File created/modified/deleted                  |
  | `:usage`            | Accounting       | Token usage (use `Event.Usage.build/3` instead)|
  | `:provider_event`   | Escape Hatch     | Unmapped provider-specific event               |

  ## Payload Conventions

  All payload keys are **strings** in **snake_case**.
  """

  alias Jido.Harness.Event

  # -- Session Lifecycle -------------------------------------------------------

  @doc "Builds a `:session_started` event."
  @spec session_started(atom(), String.t(), keyword()) :: Event.t()
  def session_started(provider, session_id, opts \\ []) do
    build(:session_started, provider, session_id, %{
      "session_id" => session_id,
      "model" => Keyword.get(opts, :model),
      "cwd" => Keyword.get(opts, :cwd),
      "tools" => Keyword.get(opts, :tools)
    }, opts)
  end

  @doc "Builds a `:session_completed` event."
  @spec session_completed(atom(), String.t(), keyword()) :: Event.t()
  def session_completed(provider, session_id, opts \\ []) do
    build(:session_completed, provider, session_id, %{
      "stop_reason" => Keyword.get(opts, :stop_reason),
      "duration_ms" => Keyword.get(opts, :duration_ms),
      "result" => Keyword.get(opts, :result)
    }, opts)
  end

  @doc "Builds a `:session_failed` event."
  @spec session_failed(atom(), String.t(), String.t(), keyword()) :: Event.t()
  def session_failed(provider, session_id, error, opts \\ []) do
    build(:session_failed, provider, session_id, %{
      "error" => error,
      "code" => Keyword.get(opts, :code)
    }, opts)
  end

  @doc "Builds a `:session_cancelled` event."
  @spec session_cancelled(atom(), String.t(), keyword()) :: Event.t()
  def session_cancelled(provider, session_id, opts \\ []) do
    build(:session_cancelled, provider, session_id, %{
      "reason" => Keyword.get(opts, :reason)
    }, opts)
  end

  # -- Content Streaming -------------------------------------------------------

  @doc "Builds an `:output_text_delta` event."
  @spec text_delta(atom(), String.t(), String.t(), keyword()) :: Event.t()
  def text_delta(provider, session_id, text, opts \\ []) do
    build(:output_text_delta, provider, session_id, %{"text" => text}, opts)
  end

  @doc "Builds an `:output_text_final` event."
  @spec text_final(atom(), String.t(), String.t(), keyword()) :: Event.t()
  def text_final(provider, session_id, text, opts \\ []) do
    build(:output_text_final, provider, session_id, %{"text" => text}, opts)
  end

  @doc "Builds a `:thinking_delta` event."
  @spec thinking_delta(atom(), String.t(), String.t(), keyword()) :: Event.t()
  def thinking_delta(provider, session_id, text, opts \\ []) do
    build(:thinking_delta, provider, session_id, %{
      "text" => text,
      "redacted" => Keyword.get(opts, :redacted, false),
      "signature" => Keyword.get(opts, :signature)
    }, opts)
  end

  # -- Tool Execution ----------------------------------------------------------

  @doc "Builds a `:tool_use_start` event."
  @spec tool_use_start(atom(), String.t(), String.t(), String.t(), map(), keyword()) :: Event.t()
  def tool_use_start(provider, session_id, name, call_id, input \\ %{}, opts \\ []) do
    build(:tool_use_start, provider, session_id, %{
      "name" => name,
      "call_id" => call_id,
      "input" => input
    }, opts)
  end

  @doc "Builds a `:tool_use_end` event."
  @spec tool_use_end(atom(), String.t(), String.t(), keyword()) :: Event.t()
  def tool_use_end(provider, session_id, call_id, opts \\ []) do
    build(:tool_use_end, provider, session_id, %{
      "call_id" => call_id,
      "output" => Keyword.get(opts, :output, ""),
      "is_error" => Keyword.get(opts, :is_error, false)
    }, opts)
  end

  # -- Turn Boundaries ---------------------------------------------------------

  @doc "Builds a `:turn_start` event."
  @spec turn_start(atom(), String.t(), keyword()) :: Event.t()
  def turn_start(provider, session_id, opts \\ []) do
    build(:turn_start, provider, session_id, %{}, opts)
  end

  @doc "Builds a `:turn_end` event."
  @spec turn_end(atom(), String.t(), keyword()) :: Event.t()
  def turn_end(provider, session_id, opts \\ []) do
    build(:turn_end, provider, session_id, %{}, opts)
  end

  # -- User Interaction --------------------------------------------------------

  @doc "Builds a `:user_message` event."
  @spec user_message(atom(), String.t(), String.t(), keyword()) :: Event.t()
  def user_message(provider, session_id, text, opts \\ []) do
    build(:user_message, provider, session_id, %{"text" => text}, opts)
  end

  @doc "Builds an `:ask_user` event."
  @spec ask_user(atom(), String.t(), keyword()) :: Event.t()
  def ask_user(provider, session_id, opts \\ []) do
    build(:ask_user, provider, session_id, %{
      "request_id" => Keyword.get(opts, :request_id),
      "questions" => Keyword.get(opts, :questions, [])
    }, opts)
  end

  # -- File Operations ---------------------------------------------------------

  @doc "Builds a `:file_change` event."
  @spec file_change(atom(), String.t(), String.t(), String.t(), keyword()) :: Event.t()
  def file_change(provider, session_id, path, action, opts \\ []) do
    build(:file_change, provider, session_id, %{
      "path" => path,
      "action" => action,
      "content" => Keyword.get(opts, :content)
    }, opts)
  end

  # -- Escape Hatch ------------------------------------------------------------

  @doc "Builds a `:provider_event` for unmapped provider-specific events."
  @spec provider_event(atom(), String.t(), String.t(), map(), keyword()) :: Event.t()
  def provider_event(provider, session_id, event_type, data \\ %{}, opts \\ []) do
    build(:provider_event, provider, session_id,
      Map.merge(data, %{"event_type" => event_type, "provider" => to_string(provider)}),
      opts)
  end

  # -- Internal ----------------------------------------------------------------

  defp build(type, provider, session_id, payload, opts) do
    payload = reject_nil_values(payload)

    extra_payload = Keyword.get(opts, :payload, %{})
    merged_payload = Map.merge(payload, extra_payload)

    Event.new!(%{
      type: type,
      provider: provider,
      session_id: session_id,
      timestamp: Keyword.get(opts, :timestamp) || DateTime.utc_now() |> DateTime.to_iso8601(),
      payload: merged_payload,
      raw: Keyword.get(opts, :raw)
    })
  end

  defp reject_nil_values(map) do
    Enum.reject(map, fn {_k, v} -> is_nil(v) end) |> Enum.into(%{})
  end
end
