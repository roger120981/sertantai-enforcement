defmodule EhsEnforcement.Scraping.Api.HseNoticeCoordinator do
  @moduledoc """
  Direct coordinator for HSE notice scraping via API.

  Implements batch processing workflow:
  1. Scrape all pages → Build aggregated list
  2. Filter against DB → Identify new/updated/existing
  3. Process new/updated only → Enrich with details/breaches
  4. Save to DB → Batch create/update

  No strategy pattern - straightforward, debuggable implementation.
  Broadcasts progress via PubSub for SSE streaming to frontend.
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Scraping.Hse.{NoticeScraper, NoticeProcessor}
  alias EhsEnforcement.Enforcement.Notice
  alias Phoenix.PubSub

  @doc """
  Scrape HSE notices in batch mode with aggregated list workflow.

  ## Parameters
    - session_id: UUID for this scraping session
    - start_page: First page to scrape (1-based)
    - max_pages: Last page to scrape
    - country: Country filter ("All", "England", "Scotland", "Wales")
    - actor: User performing the scraping (for Ash authorization)

  ## Returns
    - {:ok, %{created: count, updated: count}}
    - {:error, reason}
  """
  def scrape_batch(session_id, start_page, max_pages, country, actor \\ nil) do
    Logger.info("Starting HSE notice batch scraping",
      session_id: session_id,
      pages: "#{start_page}-#{max_pages}",
      country: country
    )

    try do
      # PHASE 1: Scrape all pages to build aggregated list
      _ =
        broadcast_progress(session_id, %{
          phase: "scraping_pages",
          total_pages: max_pages - start_page + 1
        })

      aggregated_list = scrape_all_pages(session_id, start_page, max_pages, country)

      Logger.info("Phase 1 complete: Aggregated #{length(aggregated_list)} records")

      # PHASE 2: Filter against existing DB records
      _ =
        broadcast_progress(session_id, %{
          phase: "filtering",
          records_found: length(aggregated_list)
        })

      {new_notices, updated_notices, existing_notices} = filter_against_db(aggregated_list)

      to_process = new_notices ++ updated_notices

      _ =
        broadcast_progress(session_id, %{
          phase: "filtering",
          records_to_process: length(to_process),
          records_existing: length(existing_notices)
        })

      Logger.info(
        "Phase 2 complete: #{length(new_notices)} new, #{length(updated_notices)} updated, #{length(existing_notices)} existing"
      )

      # PHASE 3: Process and save records one-by-one (real-time progress)
      _ =
        broadcast_progress(session_id, %{
          phase: "processing_records",
          records_to_process: length(to_process)
        })

      {created_count, updated_count} = process_and_save_notices(session_id, to_process, actor)

      Logger.info("Phase 3 complete: Created #{created_count}, Updated #{updated_count}")

      # Broadcast completion
      _ =
        broadcast_completed(session_id, %{
          records_found: length(aggregated_list),
          records_existing: length(existing_notices),
          records_created: created_count,
          records_updated: updated_count
        })

      {:ok, %{created: created_count, updated: updated_count}}
    rescue
      error ->
        Logger.error("HSE notice batch scraping failed: #{inspect(error)}")
        _ = broadcast_error(session_id, %{message: "Scraping failed: #{inspect(error)}"})
        {:error, error}
    end
  end

  # ============================================================================
  # PHASE 1: Scrape All Pages (Build Aggregated List)
  # ============================================================================

  defp scrape_all_pages(session_id, start_page, max_pages, country) do
    start_page..max_pages
    |> Enum.reduce([], fn page, acc ->
      _ =
        broadcast_progress(session_id, %{
          phase: "scraping_pages",
          current_page: page,
          pages_scraped: page - start_page + 1
        })

      case NoticeScraper.get_hse_notices(page_number: page, country: country) do
        notices when is_list(notices) ->
          Logger.debug("Page #{page}: Found #{length(notices)} notices")
          acc ++ notices

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

  defp filter_against_db(scraped_notices) do
    # Extract all regulator_ids for batch query
    regulator_ids =
      scraped_notices
      |> Enum.map(& &1.regulator_id)
      |> Enum.reject(&is_nil/1)

    # Single batch query for all existing notices
    existing_map =
      Notice
      |> Ash.Query.filter(regulator_id in ^regulator_ids)
      |> Ash.read!()
      |> Map.new(&{&1.regulator_id, &1})

    # Categorize: new, updated, or existing (no change)
    Enum.reduce(scraped_notices, {[], [], []}, fn notice, {new, updated, existing} ->
      case Map.get(existing_map, notice.regulator_id) do
        nil ->
          # New notice
          {[notice | new], updated, existing}

        existing_notice ->
          # Check if needs update (basic date comparison)
          if needs_update?(notice, existing_notice) do
            {new, [notice | updated], existing}
          else
            {new, updated, [notice | existing]}
          end
      end
    end)
  end

  defp needs_update?(scraped_notice, existing_notice) do
    # Simple heuristic: update if scraped action date is different
    # Can be expanded with more sophisticated comparison
    scraped_date = scraped_notice[:offence_action_date]
    existing_date = existing_notice.offence_action_date

    scraped_date != existing_date
  end

  # ============================================================================
  # PHASE 3: Process and Save Records One-by-One (Real-time Progress)
  # ============================================================================

  defp process_and_save_notices(session_id, notices_to_process, actor) do
    notices_to_process
    |> Enum.with_index()
    |> Enum.reduce({0, 0}, fn {notice, index}, {created, updated} ->
      # Step 1: Enrich with details and breaches
      enriched = enrich_notice(notice)

      # Step 2: Immediately save to database
      {new_created, new_updated} =
        case NoticeProcessor.process_and_create_notice(enriched, actor) do
          {:ok, _notice} ->
            # Successfully saved - determine if created or updated
            {created + 1, updated}

          {:error, reason} ->
            Logger.warning("Failed to save notice #{enriched.regulator_id}: #{inspect(reason)}")

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

  defp enrich_notice(basic_notice) do
    regulator_id = basic_notice.regulator_id

    # Enrich with details
    details =
      case NoticeScraper.get_notice_details(regulator_id) do
        details when is_map(details) -> details
        _ -> %{}
      end

    # Enrich with breaches
    breaches =
      case NoticeScraper.get_notice_breaches(regulator_id) do
        %{offence_breaches: breaches} when is_list(breaches) -> %{offence_breaches: breaches}
        _ -> %{offence_breaches: []}
      end

    # Merge all data
    basic_notice
    |> Map.merge(details)
    |> Map.merge(breaches)
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

  defp broadcast_record_processed(session_id, notice) do
    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:record_processed,
       %{
         regulator_id: notice.regulator_id,
         offender_name: notice[:offender_name],
         notice_type: notice[:offence_action_type]
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
