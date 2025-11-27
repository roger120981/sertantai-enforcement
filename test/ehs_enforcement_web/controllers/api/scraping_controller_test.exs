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
