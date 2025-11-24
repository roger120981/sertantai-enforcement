defmodule EhsEnforcement.Scraping.Api.EaNoticeCoordinator do
  @moduledoc """
  Direct coordinator for EA notice scraping via API.

  Implements real-time processing workflow:
  1. Scrape date range → Build aggregated list
  2. Filter against DB → Identify new/updated/existing
  3. Process and save each notice immediately → Real-time DB updates

  Each notice is saved to the database immediately after processing,
  enabling real-time progress updates to the frontend via SSE.

  No strategy pattern - straightforward, debuggable implementation.
  Broadcasts progress via PubSub for SSE streaming to frontend.
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Scraping.Ea.{NoticeScraper, NoticeProcessor}
  alias EhsEnforcement.Enforcement.Notice
  alias Phoenix.PubSub

  @doc """
  Scrape EA notices in batch mode with aggregated list workflow.

  ## Parameters
    - session_id: UUID for this scraping session
    - from_date: Start date for scraping (Date struct or string "YYYY-MM-DD")
    - to_date: End date for scraping (Date struct or string "YYYY-MM-DD")
    - actor: User performing the scraping (for Ash authorization)

  ## Returns
    - {:ok, %{created: count, updated: count}}
    - {:error, reason}
  """
  def scrape_batch(session_id, from_date, to_date, actor \\ nil) do
    # Convert string dates to Date structs if needed
    with {:ok, from_date} <- parse_date(from_date),
         {:ok, to_date} <- parse_date(to_date) do
      Logger.info("Starting EA notice batch scraping",
        session_id: session_id,
        date_range: "#{from_date} to #{to_date}"
      )

      try do
        # PHASE 1: Scrape date range to build aggregated list
        _ =
          broadcast_progress(session_id, %{
            phase: "scraping_pages",
            current_page: 1,
            total_pages: 1
          })

        aggregated_list = scrape_date_range(session_id, from_date, to_date)

        _ =
          broadcast_progress(session_id, %{
            phase: "scraping_pages",
            current_page: 1,
            pages_scraped: 1
          })

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

        # PHASE 3: Process and save each record immediately
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
          Logger.error("EA notice batch scraping failed: #{inspect(error)}")
          _ = broadcast_error(session_id, %{message: "Scraping failed: #{inspect(error)}"})
          {:error, error}
      end
    else
      {:error, reason} ->
        Logger.error("Invalid date parameters: #{inspect(reason)}")
        {:error, "Invalid date parameters: #{inspect(reason)}"}
    end
  end

  # ============================================================================
  # PHASE 1: Scrape Date Range (Build Aggregated List)
  # ============================================================================

  defp scrape_date_range(session_id, from_date, to_date) do
    case NoticeScraper.collect_summary_records(from_date, to_date) do
      {:ok, summary_records} ->
        Logger.info("Scraped #{length(summary_records)} EA notice summaries")
        summary_records

      {:error, reason} ->
        Logger.error("Failed to scrape EA notices: #{inspect(reason)}")
        _ = broadcast_error(session_id, %{message: "Scraping failed: #{inspect(reason)}"})
        []
    end
  end

  # ============================================================================
  # PHASE 2: Filter Against DB (Single Batch Query)
  # ============================================================================

  defp filter_against_db(scraped_notices) do
    # Extract all EA record IDs for batch query
    # EA uses :ea_record_id, but Notice resource stores it as :regulator_id
    ea_record_ids =
      scraped_notices
      |> Enum.map(& &1.ea_record_id)
      |> Enum.reject(&is_nil/1)

    # Single batch query for all existing notices
    existing_map =
      Notice
      |> Ash.Query.filter(regulator_id in ^ea_record_ids)
      |> Ash.read!()
      |> Map.new(&{&1.regulator_id, &1})

    # Categorize: new, updated, or existing (unchanged)
    Enum.reduce(scraped_notices, {[], [], []}, fn notice, {new, updated, existing} ->
      # Use ea_record_id from EA summary record
      case Map.get(existing_map, notice.ea_record_id) do
        nil ->
          # New notice
          {[notice | new], updated, existing}

        existing_notice ->
          # Check if needs update
          if needs_update?(notice, existing_notice) do
            {new, [notice | updated], existing}
          else
            {new, updated, [notice | existing]}
          end
      end
    end)
  end

  defp needs_update?(_scraped, _existing) do
    # Compare key fields to determine if update needed
    # For now, assume all existing records don't need updates
    # TODO: Implement proper comparison logic
    false
  end

  # ============================================================================
  # PHASE 3: Process and Save Each Record Immediately
  # ============================================================================

  defp process_and_save_notices(session_id, to_process, actor) do
    Logger.info("EA NoticeCoordinator: Processing and saving #{length(to_process)} notices")

    {created_count, updated_count} =
      to_process
      |> Enum.with_index()
      |> Enum.reduce({0, 0}, fn {summary_record, index}, {acc_created, acc_updated} ->
        Logger.debug(
          "EA NoticeCoordinator: Fetching detail for #{summary_record.ea_record_id} (#{index + 1}/#{length(to_process)})"
        )

        # Fetch and process detail record
        result =
          with {:ok, detail_record} <- NoticeScraper.fetch_detail_record(summary_record),
               {:ok, processed} <- NoticeProcessor.process_notice(detail_record) do
            Logger.debug(
              "EA NoticeCoordinator: Successfully processed #{summary_record.ea_record_id}, saving to database..."
            )

            # Immediately save to database
            case NoticeProcessor.create_notice_from_processed(processed, actor) do
              {:ok, notice, :created} ->
                Logger.info("EA NoticeCoordinator: Created notice #{notice.regulator_id}")
                new_created = acc_created + 1

                # Broadcast real-time progress update
                _ =
                  broadcast_progress(session_id, %{
                    phase: "processing_records",
                    records_processed: index + 1,
                    records_created: new_created,
                    records_updated: acc_updated
                  })

                # Broadcast individual record
                _ = broadcast_record_processed(session_id, processed)

                {:created, new_created, acc_updated}

              {:ok, notice, :updated} ->
                Logger.info("EA NoticeCoordinator: Updated notice #{notice.regulator_id}")
                new_updated = acc_updated + 1

                # Broadcast real-time progress update
                _ =
                  broadcast_progress(session_id, %{
                    phase: "processing_records",
                    records_processed: index + 1,
                    records_created: acc_created,
                    records_updated: new_updated
                  })

                # Broadcast individual record
                _ = broadcast_record_processed(session_id, processed)

                {:updated, acc_created, new_updated}

              {:ok, notice, :existing} ->
                Logger.debug("EA NoticeCoordinator: Notice already exists #{notice.regulator_id}")

                # Still broadcast progress
                _ =
                  broadcast_progress(session_id, %{
                    phase: "processing_records",
                    records_processed: index + 1,
                    records_created: acc_created,
                    records_updated: acc_updated
                  })

                {:existing, acc_created, acc_updated}

              {:error, error} ->
                Logger.error(
                  "EA NoticeCoordinator: Failed to save notice #{summary_record.ea_record_id}: #{inspect(error)}"
                )

                # Still broadcast progress
                _ =
                  broadcast_progress(session_id, %{
                    phase: "processing_records",
                    records_processed: index + 1,
                    records_created: acc_created,
                    records_updated: acc_updated
                  })

                {:error, acc_created, acc_updated}
            end
          else
            {:error, reason} ->
              Logger.warning(
                "EA NoticeCoordinator: Failed to fetch/process #{summary_record.ea_record_id}: #{inspect(reason)}"
              )

              # Broadcast progress even on failure
              _ =
                broadcast_progress(session_id, %{
                  phase: "processing_records",
                  records_processed: index + 1,
                  records_created: acc_created,
                  records_updated: acc_updated
                })

              {:error, acc_created, acc_updated}
          end

        # Update accumulator based on result
        case result do
          {:created, new_created, new_updated} -> {new_created, new_updated}
          {:updated, new_created, new_updated} -> {new_created, new_updated}
          {:existing, _, _} -> {acc_created, acc_updated}
          {:error, _, _} -> {acc_created, acc_updated}
        end
      end)

    Logger.info(
      "EA NoticeCoordinator: Complete - Created: #{created_count}, Updated: #{updated_count}"
    )

    {created_count, updated_count}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "Invalid date format. Expected YYYY-MM-DD"}
    end
  end

  defp parse_date(_), do: {:error, "Invalid date type"}

  # ============================================================================
  # PubSub Broadcasting
  # ============================================================================

  defp broadcast_progress(session_id, data) do
    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:progress, data}
    )
  end

  defp broadcast_record_processed(session_id, notice) do
    # Extract key fields for frontend display
    # Access struct fields directly
    regulator_id = notice.regulator_id

    # Debug: inspect the entire offender_attrs structure
    Logger.warning(
      "EA NoticeCoordinator: offender_attrs structure: #{inspect(notice.offender_attrs)}"
    )

    # Extract offender name from offender_attrs map
    offender_name =
      case notice.offender_attrs do
        %{offender_name: name} when is_binary(name) ->
          Logger.info("EA NoticeCoordinator: Found offender name: #{name}")
          name

        other ->
          Logger.warning(
            "EA NoticeCoordinator: No valid offender name found, got: #{inspect(other)}"
          )

          "Unknown"
      end

    record_data = %{
      regulator_id: regulator_id,
      offender_name: offender_name,
      notice_type: "Enforcement Notice"
    }

    Logger.info(
      "EA NoticeCoordinator: Broadcasting record_processed - #{regulator_id}, offender: #{offender_name}"
    )

    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:record_processed, record_data}
    )
  end

  defp broadcast_error(session_id, error_data) do
    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:error, error_data}
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
