defmodule EhsEnforcementWeb.Api.ScrapingControllerTest do
  use EhsEnforcementWeb.ConnCase

  require Ash.Query

  alias EhsEnforcement.Enforcement
  alias EhsEnforcement.Scraping.ScrapeSession

  setup do
    # Create test agencies
    {:ok, hse_agency} =
      Enforcement.create_agency(%{
        name: "Health and Safety Executive",
        code: :hse,
        base_url: "https://resources.hse.gov.uk"
      })

    {:ok, ea_agency} =
      Enforcement.create_agency(%{
        name: "Environment Agency",
        code: :ea,
        base_url: "https://environment.data.gov.uk"
      })

    %{hse_agency: hse_agency, ea_agency: ea_agency}
  end

  describe "POST /api/scraping/start - HSE convictions" do
    test "starts HSE convictions scraping session", %{conn: conn} do
      params = %{
        "agency" => "hse",
        "database" => "convictions",
        "start_page" => 1,
        "max_pages" => 2,
        "country" => "UK"
      }

      conn = post(conn, ~p"/api/scraping/start", params)

      assert json = json_response(conn, 201)
      assert json["success"] == true
      assert session_id = json["data"]["session_id"]

      # Verify session was created
      {:ok, sessions} =
        ScrapeSession
        |> Ash.Query.filter(session_id == ^session_id)
        |> Ash.read()

      assert length(sessions) == 1
      session = List.first(sessions)
      assert session.status in [:pending, :running]
    end
  end

  describe "POST /api/scraping/start - HSE appeals" do
    test "starts HSE appeals scraping session", %{conn: conn} do
      params = %{
        "agency" => "hse",
        "database" => "appeals",
        "start_page" => 1,
        "max_pages" => 2,
        "country" => "UK"
      }

      conn = post(conn, ~p"/api/scraping/start", params)

      assert json = json_response(conn, 201)
      assert json["success"] == true
      assert json["data"]["session_id"]
    end
  end

  describe "POST /api/scraping/start - EA cases" do
    test "starts EA court cases scraping session", %{conn: conn} do
      params = %{
        "agency" => "ea",
        "database" => "cases",
        "from_date" => "2024-01-01",
        "to_date" => "2024-12-31"
      }

      conn = post(conn, ~p"/api/scraping/start", params)

      assert json = json_response(conn, 201)
      assert json["success"] == true
      assert json["data"]["session_id"]
    end
  end

  describe "POST /api/scraping/start - HSE notices (already implemented)" do
    test "starts HSE notices scraping session successfully", %{conn: conn} do
      params = %{
        "agency" => "hse",
        "database" => "notices",
        "start_page" => 1,
        "max_pages" => 2,
        "country" => "UK"
      }

      conn = post(conn, ~p"/api/scraping/start", params)

      assert json = json_response(conn, 201)
      assert json["success"] == true
      assert session_id = json["data"]["session_id"]

      # Verify session was created
      {:ok, sessions} =
        ScrapeSession
        |> Ash.Query.filter(session_id == ^session_id)
        |> Ash.read()

      assert length(sessions) == 1
    end
  end

  describe "POST /api/scraping/start - EA notices (already implemented)" do
    test "starts EA notices scraping session successfully", %{conn: conn} do
      params = %{
        "agency" => "ea",
        "database" => "notices",
        "from_date" => "2024-01-01",
        "to_date" => "2024-12-31"
      }

      conn = post(conn, ~p"/api/scraping/start", params)

      assert json = json_response(conn, 201)
      assert json["success"] == true
      assert json["data"]["session_id"]
    end
  end

  describe "GET /api/scraping/sessions - EA session serialization" do
    test "includes date_from and date_to in EA session response", %{conn: conn} do
      # Create an EA session with date parameters
      from_date = ~D[2024-01-01]
      to_date = ~D[2024-12-31]

      {:ok, session} =
        ScrapeSession
        |> Ash.Changeset.for_create(:create, %{
          session_id: Ecto.UUID.generate(),
          agency: :ea,
          database: "convictions",
          status: :completed,
          start_page: 1,
          max_pages: 1,
          date_from: from_date,
          date_to: to_date
        })
        |> Ash.create()

      conn = get(conn, ~p"/api/scraping/sessions")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert [_returned_session | _] = json["data"]

      # Find our specific session
      ea_session =
        Enum.find(json["data"], fn s -> s["session_id"] == session.session_id end)

      assert ea_session, "EA session should be in response"
      assert ea_session["date_from"] == "2024-01-01"
      assert ea_session["date_to"] == "2024-12-31"
    end

    test "returns null for HSE sessions without date fields", %{conn: conn} do
      # Create an HSE session (no date parameters)
      {:ok, session} =
        ScrapeSession
        |> Ash.Changeset.for_create(:create, %{
          session_id: Ecto.UUID.generate(),
          agency: :hse,
          database: "notices",
          status: :completed,
          start_page: 1,
          max_pages: 10
        })
        |> Ash.create()

      conn = get(conn, ~p"/api/scraping/sessions")

      assert json = json_response(conn, 200)
      assert json["success"] == true

      # Find our specific session
      hse_session =
        Enum.find(json["data"], fn s -> s["session_id"] == session.session_id end)

      assert hse_session, "HSE session should be in response"
      # HSE sessions should have null date fields
      assert hse_session["date_from"] == nil
      assert hse_session["date_to"] == nil
    end
  end

  describe "POST /api/scraping/start - validation" do
    test "returns error for missing required parameters", %{conn: conn} do
      params = %{
        "agency" => "hse"
        # Missing database, start_page, etc.
      }

      conn = post(conn, ~p"/api/scraping/start", params)

      # Should return validation error
      assert conn.status in [400, 422]
    end

    test "returns error for invalid agency", %{conn: conn} do
      params = %{
        "agency" => "invalid_agency",
        "database" => "convictions"
      }

      conn = post(conn, ~p"/api/scraping/start", params)

      assert conn.status in [400, 422]
    end
  end
end
