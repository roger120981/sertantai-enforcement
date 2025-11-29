defmodule EhsEnforcementWeb.Api.ScrapingController do
  @moduledoc """
  API controller for scraping operations.

  Provides endpoints for:
  - Starting new scraping sessions
  - Stopping active sessions
  - Completing sessions (optimistic updates from frontend)
  """

  use EhsEnforcementWeb, :controller

  require Logger
  alias EhsEnforcement.Scraping.ScrapeSession
  alias EhsEnforcement.Scraping.Api.HseNoticeCoordinator
  alias EhsEnforcement.Scraping.Api.HseCaseCoordinator
  alias EhsEnforcement.Scraping.Api.EaCaseCoordinator
  alias EhsEnforcement.Scraping.Api.SepaCoordinator

  @doc """
  Start a new scraping session.

  POST /api/scraping/start

  Expected JSON body:
  {
    "agency": "hse",
    "database": "notices",
    "start_page": 1,
    "max_pages": 10,
    "country": "All"  // Optional: "All", "England", "Scotland", "Wales"
  }

  Returns:
  {
    "success": true,
    "data": {
      "session_id": "uuid-string",
      "sse_url": "/api/scraping/subscribe/uuid-string"
    }
  }
  """
  def start_scraping(conn, params) do
    Logger.info("Starting scraping session", params: params)

    with {:ok, validated_params} <- validate_params(params),
         {:ok, session} <- create_session(validated_params),
         :ok <- start_background_scraping(session, validated_params) do
      conn
      |> put_status(:created)
      |> json(%{
        success: true,
        data: %{
          session_id: session.session_id,
          sse_url: "/api/scraping/subscribe/#{session.session_id}",
          session: serialize_session(session)
        }
      })
    else
      {:error, :invalid_params, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          success: false,
          error: "Invalid parameters",
          details: reason
        })

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "Validation failed",
          details: Exception.message(error)
        })

      {:error, error} ->
        Logger.error("Failed to start scraping session: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to start scraping session",
          details: inspect(error)
        })
    end
  end

  @doc """
  Stop an active scraping session.

  DELETE /api/scraping/stop/:session_id

  Returns:
  {
    "success": true,
    "message": "Session stopped"
  }
  """
  def stop_scraping(conn, %{"session_id" => session_id}) do
    Logger.info("Stopping scraping session", session_id: session_id)

    case find_and_stop_session(session_id) do
      {:ok, _session} ->
        # Broadcast stop signal via PubSub
        _ =
          Phoenix.PubSub.broadcast(
            EhsEnforcement.PubSub,
            "scrape_session:#{session_id}",
            {:stopped, %{}}
          )

        conn
        |> json(%{
          success: true,
          message: "Session stopped"
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Session not found"
        })

      {:error, error} ->
        Logger.error("Failed to stop session: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to stop session",
          details: inspect(error)
        })
    end
  end

  @doc """
  Complete a scraping session (optimistic update from frontend).

  PATCH /api/scraping/sessions/:id/complete

  Expected JSON body:
  {
    "records_created": 5,
    "records_updated": 3
  }

  Returns:
  {
    "success": true,
    "message": "Session completed"
  }
  """
  def complete_session(conn, %{"id" => session_id} = params) do
    Logger.info("Completing scraping session", session_id: session_id)

    update_attrs = %{
      status: :completed,
      cases_created: params["records_created"] || 0,
      cases_updated: params["records_updated"] || 0
    }

    case find_and_update_session(session_id, update_attrs) do
      {:ok, session} ->
        conn
        |> json(%{
          success: true,
          message: "Session completed",
          data: serialize_session(session)
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Session not found"
        })

      {:error, error} ->
        Logger.error("Failed to complete session: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{
          success: false,
          error: "Failed to complete session",
          details: inspect(error)
        })
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp validate_params(params) do
    agency = params["agency"]

    with :ok <- validate_agency(agency),
         :ok <- validate_database(params["database"]) do
      # Branch based on agency type
      case agency do
        "hse" ->
          # HSE uses page-based parameters
          with :ok <- validate_pagination(params["start_page"], params["max_pages"]) do
            {:ok,
             %{
               agency: String.to_existing_atom(agency),
               database: params["database"],
               start_page: params["start_page"],
               max_pages: params["max_pages"],
               country: params["country"] || "All"
             }}
          end

        "ea" ->
          # EA uses date-based parameters
          with :ok <- validate_date_range(params["from_date"], params["to_date"]) do
            {:ok,
             %{
               agency: String.to_existing_atom(agency),
               database: params["database"],
               from_date: params["from_date"],
               to_date: params["to_date"]
             }}
          end

        "sepa" ->
          # SEPA is single-page, no pagination needed
          {:ok,
           %{
             agency: String.to_existing_atom(agency),
             database: "penalties",
             section: params["section"] || "all"
           }}
      end
    end
  end

  defp validate_agency(agency) when agency in ["hse", "ea", "sepa"], do: :ok

  defp validate_agency(agency),
    do:
      {:error, :invalid_params,
       "Invalid agency: #{inspect(agency)}. Must be 'hse', 'ea', or 'sepa'"}

  defp validate_database(database)
       when database in ["notices", "convictions", "appeals", "cases"],
       do: :ok

  defp validate_database(database),
    do: {:error, :invalid_params, "Invalid database: #{inspect(database)}"}

  defp validate_pagination(start_page, max_pages)
       when is_integer(start_page) and is_integer(max_pages) and start_page > 0 and
              max_pages > 0 and max_pages <= 100 do
    :ok
  end

  defp validate_pagination(_start_page, _max_pages),
    do:
      {:error, :invalid_params,
       "Invalid pagination: start_page and max_pages must be positive integers, max_pages <= 100"}

  defp validate_date_range(from_date, to_date)
       when is_binary(from_date) and is_binary(to_date) do
    with {:ok, from} <- Date.from_iso8601(from_date),
         {:ok, to} <- Date.from_iso8601(to_date),
         :ok <- validate_date_order(from, to) do
      :ok
    else
      {:error, :invalid_format} ->
        {:error, :invalid_params, "Invalid date format. Expected YYYY-MM-DD"}

      {:error, :invalid_date} ->
        {:error, :invalid_params, "Invalid date value"}

      {:error, :date_range_invalid} ->
        {:error, :invalid_params, "from_date must be before or equal to to_date"}
    end
  end

  defp validate_date_range(_from_date, _to_date),
    do: {:error, :invalid_params, "from_date and to_date must be date strings (YYYY-MM-DD)"}

  defp validate_date_order(from_date, to_date) do
    if Date.compare(from_date, to_date) in [:lt, :eq] do
      :ok
    else
      {:error, :date_range_invalid}
    end
  end

  defp create_session(params) do
    session_id = Ecto.UUID.generate()

    # Build attributes based on agency type
    base_attributes = %{
      session_id: session_id,
      agency: params.agency,
      database: params.database,
      status: :pending
    }

    attributes =
      case params.agency do
        :hse ->
          # HSE uses page-based parameters
          Map.merge(base_attributes, %{
            start_page: params.start_page,
            max_pages: params.max_pages
          })

        :ea ->
          # EA uses date-based parameters
          Map.merge(base_attributes, %{
            start_page: 1,
            max_pages: 1,
            date_from: params.from_date,
            date_to: params.to_date
          })

        :sepa ->
          # SEPA is single-page scraping
          Map.merge(base_attributes, %{
            start_page: 1,
            max_pages: 1
          })
      end

    ScrapeSession
    |> Ash.Changeset.for_create(:create, attributes)
    |> Ash.create()
  end

  defp start_background_scraping(session, params) do
    # Start async task for scraping
    _ =
      Task.start(fn ->
        try do
          # Update session to running
          _ =
            session
            |> Ash.Changeset.for_update(:update, %{status: :running})
            |> Ash.update()

          # Call coordinator based on agency + database
          result =
            case {params.agency, params.database} do
              {:hse, "notices"} ->
                HseNoticeCoordinator.scrape_batch(
                  session.session_id,
                  params.start_page,
                  params.max_pages,
                  params.country,
                  nil
                )

              {:hse, "convictions"} ->
                HseCaseCoordinator.scrape_batch(
                  session.session_id,
                  params.start_page,
                  params.max_pages,
                  params.database,
                  nil
                )

              {:hse, "appeals"} ->
                HseCaseCoordinator.scrape_batch(
                  session.session_id,
                  params.start_page,
                  params.max_pages,
                  params.database,
                  nil
                )

              {:ea, "notices"} ->
                alias EhsEnforcement.Scraping.Api.EaNoticeCoordinator

                EaNoticeCoordinator.scrape_batch(
                  session.session_id,
                  params.from_date,
                  params.to_date,
                  nil
                )

              {:ea, "cases"} ->
                EaCaseCoordinator.scrape_batch(
                  session.session_id,
                  params.from_date,
                  params.to_date,
                  nil,
                  nil
                )

              {:sepa, "penalties"} ->
                SepaCoordinator.scrape_batch(
                  session.session_id,
                  params.section,
                  nil
                )

              _other ->
                {:error, :not_implemented}
            end

          # Handle result
          case result do
            {:ok, %{created: created, updated: updated}} ->
              _ =
                session
                |> Ash.Changeset.for_update(:update, %{
                  status: :completed,
                  cases_created: created,
                  cases_updated: updated
                })
                |> Ash.update()

            {:error, reason} ->
              Logger.error(
                "Scraping failed for session #{session.session_id}: #{inspect(reason)}"
              )

              _ =
                session
                |> Ash.Changeset.for_update(:update, %{status: :failed})
                |> Ash.update()
          end
        rescue
          error ->
            Logger.error("Scraping crashed for session #{session.session_id}: #{inspect(error)}")

            _ =
              session
              |> Ash.Changeset.for_update(:update, %{status: :failed})
              |> Ash.update()
        end
      end)

    :ok
  end

  defp find_and_stop_session(session_id) do
    require Ash.Query

    case ScrapeSession
         |> Ash.Query.filter(session_id == ^session_id)
         |> Ash.read() do
      {:ok, [session]} ->
        session
        |> Ash.Changeset.for_update(:mark_stopped)
        |> Ash.update()

      {:ok, []} ->
        {:error, :not_found}

      {:error, error} ->
        {:error, error}
    end
  end

  defp find_and_update_session(session_id, attrs) do
    require Ash.Query

    case ScrapeSession
         |> Ash.Query.filter(session_id == ^session_id)
         |> Ash.read() do
      {:ok, [session]} ->
        session
        |> Ash.Changeset.for_update(:update, attrs)
        |> Ash.update()

      {:ok, []} ->
        {:error, :not_found}

      {:error, error} ->
        {:error, error}
    end
  end

  defp serialize_session(session) do
    %{
      id: session.id,
      session_id: session.session_id,
      agency: session.agency,
      database: session.database,
      start_page: session.start_page,
      max_pages: session.max_pages,
      status: session.status,
      current_page: session.current_page,
      pages_processed: session.pages_processed,
      cases_found: session.cases_found,
      cases_processed: session.cases_processed,
      cases_created: session.cases_created,
      cases_updated: session.cases_updated,
      cases_exist_total: session.cases_exist_total,
      errors_count: session.errors_count,
      inserted_at: session.inserted_at,
      updated_at: session.updated_at
    }
  end
end
