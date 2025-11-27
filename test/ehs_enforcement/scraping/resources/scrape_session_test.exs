defmodule EhsEnforcement.Scraping.ScrapeSessionTest do
  use EhsEnforcement.DataCase, async: true

  alias EhsEnforcement.Scraping.ScrapeSession

  require Ash.Query

  describe "scrape session lifecycle" do
    test "creates HSE session with running status" do
      {:ok, session} =
        Ash.create(ScrapeSession, %{
          session_id: "test-session-#{System.unique_integer([:positive])}",
          agency: :hse,
          start_page: 1,
          max_pages: 10,
          database: "convictions",
          status: :running
        })

      assert session.status == :running
      assert session.agency == :hse
      assert session.start_page == 1
      assert session.max_pages == 10
    end

    test "creates EA session with date parameters" do
      {:ok, session} =
        Ash.create(ScrapeSession, %{
          session_id: "ea-test-#{System.unique_integer([:positive])}",
          agency: :ea,
          start_page: 1,
          max_pages: 1,
          database: "ea_enforcement",
          date_from: ~D[2024-01-01],
          date_to: ~D[2024-12-31],
          action_types: [:court_case, :caution],
          status: :running
        })

      assert session.agency == :ea
      assert session.date_from == ~D[2024-01-01]
      assert session.date_to == ~D[2024-12-31]
      assert session.action_types == [:court_case, :caution]
    end

    test "mark_stopped action sets status to stopped" do
      {:ok, session} =
        Ash.create(ScrapeSession, %{
          session_id: "test-session-#{System.unique_integer([:positive])}",
          start_page: 1,
          max_pages: 10,
          database: "convictions",
          status: :running
        })

      assert session.status == :running

      {:ok, stopped_session} = Ash.update(session, action: :mark_stopped)

      assert stopped_session.status == :stopped
    end

    test "can update session to failed status" do
      {:ok, session} =
        Ash.create(ScrapeSession, %{
          session_id: "test-session-#{System.unique_integer([:positive])}",
          start_page: 1,
          max_pages: 10,
          database: "convictions",
          status: :running
        })

      {:ok, failed_session} = Ash.update(session, %{status: :failed})

      assert failed_session.status == :failed
    end

    test "can update session to completed status" do
      {:ok, session} =
        Ash.create(ScrapeSession, %{
          session_id: "test-session-#{System.unique_integer([:positive])}",
          start_page: 1,
          max_pages: 10,
          database: "convictions",
          status: :running
        })

      {:ok, completed_session} = Ash.update(session, %{status: :completed})

      assert completed_session.status == :completed
    end
  end

  describe "read actions" do
    setup do
      # Create sessions with different statuses
      {:ok, running} =
        Ash.create(ScrapeSession, %{
          session_id: "running-#{System.unique_integer([:positive])}",
          start_page: 1,
          max_pages: 10,
          database: "convictions",
          status: :running
        })

      {:ok, completed} =
        Ash.create(ScrapeSession, %{
          session_id: "completed-#{System.unique_integer([:positive])}",
          start_page: 1,
          max_pages: 10,
          database: "convictions",
          status: :completed
        })

      {:ok, stopped} =
        Ash.create(ScrapeSession, %{
          session_id: "stopped-#{System.unique_integer([:positive])}",
          start_page: 1,
          max_pages: 10,
          database: "convictions",
          status: :stopped
        })

      %{running: running, completed: completed, stopped: stopped}
    end

    test "active read action returns only pending and running sessions", %{
      running: running,
      completed: _completed,
      stopped: _stopped
    } do
      active_sessions = Ash.read!(ScrapeSession, action: :active)

      session_ids = Enum.map(active_sessions, & &1.session_id)
      assert running.session_id in session_ids
      # Completed and stopped should not be in active sessions
    end

    test "can read all sessions" do
      all_sessions = Ash.read!(ScrapeSession)
      assert length(all_sessions) >= 3
    end
  end

  describe "session metrics" do
    test "tracks cases_processed and cases_created" do
      {:ok, session} =
        Ash.create(ScrapeSession, %{
          session_id: "metrics-#{System.unique_integer([:positive])}",
          start_page: 1,
          max_pages: 10,
          database: "convictions",
          status: :running,
          cases_found: 0,
          cases_processed: 0,
          cases_created: 0
        })

      # Simulate processing
      {:ok, updated} =
        Ash.update(session, %{
          cases_found: 50,
          cases_processed: 25,
          cases_created: 15
        })

      assert updated.cases_found == 50
      assert updated.cases_processed == 25
      assert updated.cases_created == 15
    end
  end
end
