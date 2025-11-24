defmodule EhsEnforcementWeb.ScrapingSSEController do
  @moduledoc """
  Server-Sent Events (SSE) controller for real-time scraping progress updates.

  Subscribes to PubSub topic for a specific scraping session and streams
  progress events to the frontend client.

  ## Event Types
    - progress: Phase updates, counters, percentages
    - record_processed: Individual record completion
    - error: Scraping errors with details
    - completed: Session completion summary
    - stopped: Manual stop signal

  ## Usage
    GET /api/scraping/subscribe/:session_id
    → Opens SSE stream
    → Returns events as server-sent-events stream
    → Auto-closes on completion or error
  """

  use EhsEnforcementWeb, :controller

  require Logger
  alias Phoenix.PubSub

  @doc """
  Subscribe to scraping progress events via SSE.

  Opens a long-lived HTTP connection and streams events as they arrive from PubSub.
  """
  def subscribe(conn, %{"session_id" => session_id}) do
    Logger.info("SSE subscription opened for session: #{session_id}")

    # Set SSE headers
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      # Disable nginx buffering
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    # Subscribe to session-specific PubSub topic
    :ok = PubSub.subscribe(EhsEnforcement.PubSub, "scrape_session:#{session_id}")

    # Stream events until completion or error
    stream_events(conn, session_id)
  end

  # ============================================================================
  # Event Streaming Loop
  # ============================================================================

  defp stream_events(conn, session_id) do
    receive do
      {:progress, data} ->
        case send_sse_event(conn, "progress", data) do
          {:ok, conn} ->
            stream_events(conn, session_id)

          {:error, reason} ->
            Logger.warning("SSE connection lost for session #{session_id}: #{inspect(reason)}")
            conn
        end

      {:record_processed, notice_data} ->
        case send_sse_event(conn, "record_processed", notice_data) do
          {:ok, conn} -> stream_events(conn, session_id)
          {:error, _reason} -> conn
        end

      {:error, error_data} ->
        case send_sse_event(conn, "error", error_data) do
          {:ok, conn} -> stream_events(conn, session_id)
          {:error, _reason} -> conn
        end

      {:completed, summary} ->
        Logger.info("SSE session completed: #{session_id}")

        case send_sse_event(conn, "completed", summary) do
          {:ok, conn} ->
            # Send final event and close connection
            PubSub.unsubscribe(EhsEnforcement.PubSub, "scrape_session:#{session_id}")
            conn

          {:error, _reason} ->
            conn
        end

      {:stopped, _} ->
        Logger.info("SSE session stopped: #{session_id}")
        _ = send_sse_event(conn, "stopped", %{})
        PubSub.unsubscribe(EhsEnforcement.PubSub, "scrape_session:#{session_id}")
        conn

      _other ->
        # Unknown message, ignore and continue
        stream_events(conn, session_id)
    after
      # Ping client every 30 seconds to keep connection alive
      30_000 ->
        case send_sse_ping(conn) do
          {:ok, conn} -> stream_events(conn, session_id)
          {:error, _reason} -> conn
        end
    end
  end

  # ============================================================================
  # SSE Event Formatting
  # ============================================================================

  defp send_sse_event(conn, event_name, data) do
    # Format as SSE: event: name\ndata: json\n\n
    event_string = """
    event: #{event_name}
    data: #{Jason.encode!(data)}

    """

    chunk(conn, event_string)
  end

  defp send_sse_ping(conn) do
    # Send comment as keepalive (clients ignore comments)
    chunk(conn, ": ping\n\n")
  end
end
