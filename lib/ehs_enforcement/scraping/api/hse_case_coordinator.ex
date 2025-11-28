defmodule EhsEnforcement.Scraping.Api.HseCaseCoordinator do
  @moduledoc """
  Direct coordinator for HSE case scraping via API.

  Implements batch processing workflow:
  1. Scrape all pages → Build aggregated list
  2. Filter against DB → Identify new/updated/existing
  3. Process new/updated only → Enrich with details/breaches/related cases
  4. Save to DB → Batch create/update

  No strategy pattern - straightforward, debuggable implementation.
  Broadcasts progress via PubSub for SSE streaming to frontend.
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Scraping.Hse.{CaseScraper, CaseProcessor}
  alias EhsEnforcement.Enforcement.Case
  alias Phoenix.PubSub

  @doc """
  Scrape HSE cases in batch mode with aggregated list workflow.

  ## Parameters
    - session_id: UUID for this scraping session
    - start_page: First page to scrape (1-based)
    - max_pages: Last page to scrape
    - database: Database type ("convictions", "appeals", etc.)
    - actor: User performing the scraping (for Ash authorization)

  ## Returns
    - {:ok, %{created: count, updated: count}}
    - {:error, reason}
  """
  def scrape_batch(session_id, start_page, max_pages, database, actor \\ nil) do
    Logger.info("Starting HSE case batch scraping",
      session_id: session_id,
      pages: "#{start_page}-#{max_pages}",
      database: database
    )

    try do
      # PHASE 1: Scrape all pages to build aggregated list
      _ =
        broadcast_progress(session_id, %{
          phase: "scraping_pages",
          total_pages: max_pages - start_page + 1
        })

      aggregated_list = scrape_all_pages(session_id, start_page, max_pages, database)

      Logger.info("Phase 1 complete: Aggregated #{length(aggregated_list)} records")

      # PHASE 2: Filter against existing DB records
      _ =
        broadcast_progress(session_id, %{
          phase: "filtering",
          records_found: length(aggregated_list)
        })

      {new_cases, updated_cases, existing_cases} = filter_against_db(aggregated_list)

      to_process = new_cases ++ updated_cases

      _ =
        broadcast_progress(session_id, %{
          phase: "filtering",
          records_to_process: length(to_process),
          records_existing: length(existing_cases)
        })

      Logger.info(
        "Phase 2 complete: #{length(new_cases)} new, #{length(updated_cases)} updated, #{length(existing_cases)} existing"
      )

      # PHASE 3: Process and save records one-by-one (real-time progress)
      _ =
        broadcast_progress(session_id, %{
          phase: "processing_records",
          records_to_process: length(to_process)
        })

      {created_count, updated_count} =
        process_and_save_cases(session_id, to_process, database, actor)

      Logger.info("Phase 3 complete: Created #{created_count}, Updated #{updated_count}")

      # Broadcast completion
      _ =
        broadcast_completed(session_id, %{
          records_found: length(aggregated_list),
          records_existing: length(existing_cases),
          records_created: created_count,
          records_updated: updated_count
        })

      {:ok, %{created: created_count, updated: updated_count}}
    rescue
      error ->
        Logger.error("HSE case batch scraping failed: #{inspect(error)}")
        _ = broadcast_error(session_id, %{message: "Scraping failed: #{inspect(error)}"})
        {:error, error}
    end
  end

  # ============================================================================
  # PHASE 1: Scrape All Pages (Build Aggregated List)
  # ============================================================================

  defp scrape_all_pages(session_id, start_page, max_pages, database) do
    start_page..max_pages
    |> Enum.reduce([], fn page, acc ->
      _ =
        broadcast_progress(session_id, %{
          phase: "scraping_pages",
          current_page: page,
          pages_scraped: page - start_page + 1
        })

      case CaseScraper.scrape_page_basic(page, database: database) do
        {:ok, cases} when is_list(cases) ->
          Logger.debug("Page #{page}: Found #{length(cases)} cases")
          acc ++ cases

        {:error, reason} ->
          Logger.warning("Page #{page} failed: #{inspect(reason)}")
          _ = broadcast_error(session_id, %{page: page, message: inspect(reason)})
          acc

        _other ->
          Logger.warning("Page #{page}: Unexpected response")
          acc
      end
    end)
  end

  # ============================================================================
  # PHASE 2: Filter Against DB (Single Batch Query)
  # ============================================================================

  defp filter_against_db(scraped_cases) do
    # Extract all regulator_ids for batch query
    regulator_ids =
      scraped_cases
      |> Enum.map(& &1.regulator_id)
      |> Enum.reject(&is_nil/1)

    # Single batch query for all existing cases
    existing_map =
      Case
      |> Ash.Query.filter(regulator_id in ^regulator_ids)
      |> Ash.read!()
      |> Map.new(&{&1.regulator_id, &1})

    # Categorize: new, updated, or existing (no change)
    Enum.reduce(scraped_cases, {[], [], []}, fn case_record, {new, updated, existing} ->
      case Map.get(existing_map, case_record.regulator_id) do
        nil ->
          # New case
          {[case_record | new], updated, existing}

        existing_case ->
          # Check if needs update (basic date comparison)
          if needs_update?(case_record, existing_case) do
            {new, [case_record | updated], existing}
          else
            {new, updated, [case_record | existing]}
          end
      end
    end)
  end

  defp needs_update?(scraped_case, existing_case) do
    # Simple heuristic: update if scraped action date is different
    # Can be expanded with more sophisticated comparison
    scraped_date = scraped_case.offence_action_date
    existing_date = existing_case.offence_action_date

    scraped_date != existing_date
  end

  # ============================================================================
  # PHASE 3: Process and Save Records One-by-One (Real-time Progress)
  # ============================================================================

  defp process_and_save_cases(session_id, cases_to_process, database, actor) do
    cases_to_process
    |> Enum.with_index()
    |> Enum.reduce({0, 0}, fn {case_record, index}, {created, updated} ->
      # Step 1: Enrich with details, breaches, and related cases
      enriched = enrich_case(case_record, database)

      # Step 2: Immediately save to database
      {new_created, new_updated} =
        case CaseProcessor.process_and_create_case(enriched, actor) do
          {:ok, _case} ->
            # Successfully saved - determine if created or updated
            # (Could be improved with explicit action tracking from processor)
            {created + 1, updated}

          {:error, reason} ->
            Logger.warning("Failed to save case #{enriched.regulator_id}: #{inspect(reason)}")

            _ =
              broadcast_error(session_id, %{
                regulator_id: enriched.regulator_id,
                message: inspect(reason)
              })

            # No change to counters on error
            {created, updated}
        end

      # Step 3: Broadcast real-time progress after each save
      _ =
        broadcast_progress(session_id, %{
          phase: "processing_records",
          records_processed: index + 1,
          records_created: new_created,
          records_updated: new_updated
        })

      # Broadcast individual record processed
      _ = broadcast_record_processed(session_id, enriched)

      {new_created, new_updated}
    end)
  end

  defp enrich_case(basic_case, database) do
    regulator_id = basic_case.regulator_id

    # Enrich with full details (includes breaches and related cases)
    case CaseScraper.scrape_case_details(regulator_id, database, []) do
      {:ok, details} when is_map(details) ->
        # Merge basic case with enriched details
        Map.merge(basic_case, details)

      {:error, reason} ->
        Logger.warning(
          "Failed to enrich case #{regulator_id}: #{inspect(reason)}, using basic data only"
        )

        basic_case

      _ ->
        basic_case
    end
  end

  # ============================================================================
  # PubSub Broadcasting (for SSE)
  # ============================================================================

  defp broadcast_progress(session_id, data) do
    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:progress, data}
    )
  end

  defp broadcast_record_processed(session_id, case_record) do
    # Handle both struct and map cases (enriched details may return map)
    offender_name = Map.get(case_record, :offender_name)
    action_type = Map.get(case_record, :offence_action_type)

    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:record_processed,
       %{
         regulator_id: case_record.regulator_id,
         offender_name: offender_name,
         action_type: action_type
       }}
    )
  end

  defp broadcast_error(session_id, error) do
    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:error, Map.put(error, :timestamp, DateTime.utc_now())}
    )
  end

  defp broadcast_completed(session_id, summary) do
    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:completed, summary}
    )
  end
end
