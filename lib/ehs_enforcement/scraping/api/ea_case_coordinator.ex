defmodule EhsEnforcement.Scraping.Api.EaCaseCoordinator do
  @moduledoc """
  Direct coordinator for EA case scraping via API.

  Implements two-stage workflow:
  1. Scrape summary records → Build aggregated list (Stage 1)
  2. Filter against DB → Identify new/updated/existing
  3. Fetch detail records and save one-by-one → Real-time progress (Stage 2)

  EA-specific characteristics:
  - Date-range based (not page-based like HSE)
  - Single summary request returns ALL results (no pagination)
  - Enrichment via detail page requests

  No strategy pattern - straightforward, debuggable implementation.
  Broadcasts progress via PubSub for SSE streaming to frontend.
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Scraping.Ea.{CaseScraper, CaseProcessor}
  alias EhsEnforcement.Enforcement.Case
  alias Phoenix.PubSub

  @doc """
  Scrape EA cases in batch mode with date-range workflow.

  ## Parameters
    - session_id: UUID for this scraping session
    - date_from: Start date (ISO8601 string "YYYY-MM-DD")
    - date_to: End date (ISO8601 string "YYYY-MM-DD")
    - action_types: List of action types (optional, defaults to all)
    - actor: User performing the scraping (for Ash authorization)

  ## Returns
    - {:ok, %{created: count, updated: count}}
    - {:error, reason}
  """
  def scrape_batch(session_id, date_from, date_to, action_types \\ nil, actor \\ nil) do
    # Default to all action types if not specified
    action_types = action_types || [:court_case, :caution, :enforcement_notice]

    # Parse dates from strings if needed
    {date_from, date_to} = parse_dates(date_from, date_to)

    Logger.info("Starting EA case batch scraping",
      session_id: session_id,
      date_from: date_from,
      date_to: date_to,
      action_types: action_types
    )

    try do
      # PHASE 1: Scrape summary records (Stage 1 - single request per action type)
      _ =
        broadcast_progress(session_id, %{
          phase: "scraping_summaries",
          action_types: length(action_types)
        })

      case scrape_all_summaries(session_id, date_from, date_to, action_types) do
        {:ok, summary_records} ->
          Logger.info("Phase 1 complete: #{length(summary_records)} summary records collected")

          # PHASE 2: Filter against existing DB records
          _ =
            broadcast_progress(session_id, %{
              phase: "filtering",
              records_found: length(summary_records)
            })

          {new_records, updated_records, existing_records} =
            filter_against_db(summary_records)

          to_process = new_records ++ updated_records

          _ =
            broadcast_progress(session_id, %{
              phase: "filtering",
              records_to_process: length(to_process),
              records_existing: length(existing_records)
            })

          Logger.info(
            "Phase 2 complete: #{length(new_records)} new, #{length(updated_records)} updated, #{length(existing_records)} existing"
          )

          # PHASE 3: Fetch details and save one-by-one (real-time progress)
          _ =
            broadcast_progress(session_id, %{
              phase: "processing_records",
              records_to_process: length(to_process)
            })

          {created_count, updated_count} =
            fetch_details_and_save(session_id, to_process, actor)

          Logger.info("Phase 3 complete: Created #{created_count}, Updated #{updated_count}")

          # Broadcast completion
          _ =
            broadcast_completed(session_id, %{
              records_found: length(summary_records),
              records_existing: length(existing_records),
              records_created: created_count,
              records_updated: updated_count
            })

          {:ok, %{created: created_count, updated: updated_count}}

        {:error, reason} ->
          Logger.error("EA case batch scraping failed: #{inspect(reason)}")
          _ = broadcast_error(session_id, %{message: "Scraping failed: #{inspect(reason)}"})
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("EA case batch scraping crashed: #{inspect(error)}")
        _ = broadcast_error(session_id, %{message: "Scraping crashed: #{inspect(error)}"})
        {:error, error}
    end
  end

  # ============================================================================
  # PHASE 1: Scrape Summary Records (EA Stage 1 - Single Request per Action Type)
  # ============================================================================

  defp scrape_all_summaries(session_id, date_from, date_to, action_types) do
    Logger.debug("Stage 1: Collecting summary records for #{length(action_types)} action types")

    results =
      Enum.reduce_while(action_types, {:ok, []}, fn action_type, {:ok, acc} ->
        _ =
          broadcast_progress(session_id, %{
            phase: "scraping_summaries",
            current_action_type: action_type
          })

        Logger.info("Scraping EA #{action_type} for #{date_from} to #{date_to}")

        case CaseScraper.collect_summary_records_for_action_type(
               date_from,
               date_to,
               action_type,
               []
             ) do
          {:ok, records} ->
            Logger.info("Action type #{action_type}: Found #{length(records)} records")
            {:cont, {:ok, acc ++ records}}

          {:error, reason} ->
            Logger.error("Failed to scrape action type #{action_type}: #{inspect(reason)}")

            _ = broadcast_error(session_id, %{action_type: action_type, message: inspect(reason)})
            {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, all_records} ->
        # Remove duplicates based on EA record ID
        unique_records = Enum.uniq_by(all_records, & &1.ea_record_id)

        Logger.info(
          "Stage 1 deduplication: #{length(all_records)} → #{length(unique_records)} unique records"
        )

        {:ok, unique_records}

      error ->
        error
    end
  end

  # ============================================================================
  # PHASE 2: Filter Against DB (Single Batch Query)
  # ============================================================================

  defp filter_against_db(summary_records) do
    # Extract all EA record IDs for batch query
    ea_record_ids =
      summary_records
      |> Enum.map(& &1.ea_record_id)
      |> Enum.reject(&is_nil/1)

    # Single batch query for all existing cases
    # EA cases use EA record ID as regulator_id
    existing_map =
      Case
      |> Ash.Query.filter(regulator_id in ^ea_record_ids)
      |> Ash.read!()
      |> Map.new(&{&1.regulator_id, &1})

    # Categorize: new, updated, or existing (no change)
    Enum.reduce(summary_records, {[], [], []}, fn record, {new, updated, existing} ->
      case Map.get(existing_map, record.ea_record_id) do
        nil ->
          # New record
          {[record | new], updated, existing}

        existing_case ->
          # Check if needs update (date comparison)
          if needs_update?(record, existing_case) do
            {new, [record | updated], existing}
          else
            {new, updated, [record | existing]}
          end
      end
    end)
  end

  defp needs_update?(summary_record, existing_case) do
    # Simple heuristic: update if action date is different
    # EA summary records have action_date field
    summary_date = summary_record.action_date
    existing_date = existing_case.offence_action_date

    summary_date != existing_date
  end

  # ============================================================================
  # PHASE 3: Fetch Details and Save One-by-One (EA Stage 2 + DB Save)
  # ============================================================================

  defp fetch_details_and_save(session_id, summary_records, actor) do
    summary_records
    |> Enum.with_index()
    |> Enum.reduce({0, 0}, fn {summary_record, index}, {created, updated} ->
      # Step 1: Fetch detail record from EA website
      enriched =
        case CaseScraper.fetch_detail_record_individual(summary_record, []) do
          {:ok, detail_record} ->
            detail_record

          {:error, reason} ->
            Logger.warning(
              "Failed to fetch detail for EA record #{summary_record.ea_record_id}: #{inspect(reason)}, using summary data only"
            )

            # Fallback: use summary data (will have limited fields)
            summary_record
        end

      # Step 2: Immediately process and save to database
      {new_created, new_updated} =
        case CaseProcessor.process_and_create_case(enriched, actor) do
          {:ok, _case} ->
            # Successfully saved - determine if created or updated
            # (Could be improved with explicit action tracking from processor)
            {created + 1, updated}

          {:error, reason} ->
            Logger.warning("Failed to save EA case #{enriched.ea_record_id}: #{inspect(reason)}")

            _ =
              broadcast_error(session_id, %{
                ea_record_id: enriched.ea_record_id,
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

  defp broadcast_record_processed(session_id, ea_record) do
    # Handle both EaSummaryRecord and EaDetailRecord structs
    offender_name =
      if is_struct(ea_record),
        do: Map.get(ea_record, :offender_name),
        else: ea_record[:offender_name]

    action_type =
      if is_struct(ea_record),
        do: Map.get(ea_record, :action_type),
        else: ea_record[:action_type]

    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:record_processed,
       %{
         regulator_id: ea_record.ea_record_id,
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

  # ============================================================================
  # Utility Functions
  # ============================================================================

  defp parse_dates(date_from, date_to) do
    # Handle both string and Date formats
    date_from =
      case date_from do
        %Date{} = d -> d
        str when is_binary(str) -> Date.from_iso8601!(str)
      end

    date_to =
      case date_to do
        %Date{} = d -> d
        str when is_binary(str) -> Date.from_iso8601!(str)
      end

    {date_from, date_to}
  end
end
