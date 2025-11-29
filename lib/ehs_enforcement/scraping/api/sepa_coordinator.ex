defmodule EhsEnforcement.Scraping.Api.SepaCoordinator do
  @moduledoc """
  Direct coordinator for SEPA penalty scraping via API.

  SEPA publishes all enforcement data on a single page, so this coordinator
  is simpler than HSE/EA - no pagination or date ranges needed.

  Implements workflow:
  1. Scrape single page → Get all penalties/undertakings/costs recovery
  2. Filter against DB → Identify new/updated/existing
  3. Process and save → Create Notice records
  4. Broadcast progress → SSE streaming to frontend
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Scraping.Sepa.{SepaPenaltyScraper, SepaPenaltyProcessor}
  alias EhsEnforcement.Enforcement.Notice
  alias Phoenix.PubSub

  @doc """
  Scrape SEPA penalties with full workflow.

  ## Parameters
    - session_id: UUID for this scraping session
    - section: Section filter - "all", "penalties", "undertakings", "costs_recovery"
    - actor: User performing the scraping (for Ash authorization)

  ## Returns
    - {:ok, %{created: count, updated: count}}
    - {:error, reason}
  """
  def scrape_batch(session_id, section \\ "all", actor \\ nil) do
    section_atom = parse_section(section)

    Logger.info("Starting SEPA penalty scraping",
      session_id: session_id,
      section: section_atom
    )

    try do
      # PHASE 1: Scrape single page
      _ =
        broadcast_progress(session_id, %{
          phase: "scraping_page",
          message: "Fetching SEPA enforcement data..."
        })

      scraped_records = scrape_page(session_id, section_atom)

      Logger.info("Phase 1 complete: Scraped #{length(scraped_records)} records")

      # PHASE 2: Filter against existing DB records
      _ =
        broadcast_progress(session_id, %{
          phase: "filtering",
          records_found: length(scraped_records)
        })

      {new_records, updated_records, existing_records} = filter_against_db(scraped_records)

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

      # PHASE 3: Process and save records one-by-one (real-time progress)
      _ =
        broadcast_progress(session_id, %{
          phase: "processing_records",
          records_to_process: length(to_process)
        })

      {created_count, updated_count} = process_and_save_penalties(session_id, to_process, actor)

      Logger.info("Phase 3 complete: Created #{created_count}, Updated #{updated_count}")

      # Broadcast completion
      _ =
        broadcast_completed(session_id, %{
          records_found: length(scraped_records),
          records_existing: length(existing_records),
          records_created: created_count,
          records_updated: updated_count
        })

      {:ok, %{created: created_count, updated: updated_count}}
    rescue
      error ->
        Logger.error("SEPA penalty scraping failed: #{inspect(error)}")
        _ = broadcast_error(session_id, %{message: "Scraping failed: #{inspect(error)}"})
        {:error, error}
    end
  end

  # ============================================================================
  # PHASE 1: Scrape Single Page
  # ============================================================================

  defp scrape_page(session_id, section_atom) do
    case SepaPenaltyScraper.scrape_all(section: section_atom) do
      {:ok, records} ->
        _ =
          broadcast_progress(session_id, %{
            phase: "scraping_page",
            records_scraped: length(records)
          })

        records

      {:error, reason} ->
        Logger.warning("SEPA scraping failed: #{inspect(reason)}")
        _ = broadcast_error(session_id, %{message: "Scraping error: #{inspect(reason)}"})
        []
    end
  end

  # ============================================================================
  # PHASE 2: Filter Against DB (Single Batch Query)
  # ============================================================================

  defp filter_against_db(scraped_records) do
    # Process all scraped records to get regulator_ids
    processed_with_ids =
      scraped_records
      |> Enum.map(fn record ->
        case SepaPenaltyProcessor.process_penalty(record) do
          {:ok, processed} -> {record, processed.regulator_id}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    regulator_ids = Enum.map(processed_with_ids, fn {_record, id} -> id end)

    # Single batch query for all existing notices
    existing_map =
      Notice
      |> Ash.Query.filter(regulator_id in ^regulator_ids)
      |> Ash.read!()
      |> Map.new(&{&1.regulator_id, &1})

    # Categorize: new, updated, or existing (no change)
    Enum.reduce(processed_with_ids, {[], [], []}, fn {record, regulator_id},
                                                     {new, updated, existing} ->
      case Map.get(existing_map, regulator_id) do
        nil ->
          # New record
          {[record | new], updated, existing}

        existing_notice ->
          # Check if needs update (basic comparison)
          if needs_update?(record, existing_notice) do
            {new, [record | updated], existing}
          else
            {new, updated, [record | existing]}
          end
      end
    end)
  end

  defp needs_update?(scraped_record, existing_notice) do
    # Simple heuristic: update if penalty amount differs (for penalties)
    # or if offence details differ
    scraped_amount = scraped_record.penalty_amount
    existing_amount = existing_notice.penalty_amount

    # Only consider as needing update if there's a meaningful difference
    scraped_amount != existing_amount
  end

  # ============================================================================
  # PHASE 3: Process and Save Records One-by-One (Real-time Progress)
  # ============================================================================

  defp process_and_save_penalties(session_id, records_to_process, actor) do
    records_to_process
    |> Enum.with_index()
    |> Enum.reduce({0, 0}, fn {record, index}, {created, updated} ->
      # Process and save using processor
      {new_created, new_updated} =
        case SepaPenaltyProcessor.process_and_create_penalty(record, actor) do
          {:ok, _notice} ->
            # Successfully saved
            {created + 1, updated}

          {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidAttribute{} | _]}} ->
            # Likely a duplicate - count as existing/updated
            {created, updated}

          {:error, reason} ->
            Logger.warning("Failed to save SEPA penalty: #{inspect(reason)}")

            _ =
              broadcast_error(session_id, %{
                name: record.name_and_address,
                message: inspect(reason)
              })

            # No change to counters on error
            {created, updated}
        end

      # Broadcast real-time progress after each save
      _ =
        broadcast_progress(session_id, %{
          phase: "processing_records",
          records_processed: index + 1,
          records_created: new_created,
          records_updated: new_updated
        })

      # Broadcast individual record processed
      _ = broadcast_record_processed(session_id, record)

      {new_created, new_updated}
    end)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp parse_section("all"), do: :all
  defp parse_section("penalties"), do: :penalties
  defp parse_section("undertakings"), do: :undertakings
  defp parse_section("costs_recovery"), do: :costs_recovery
  defp parse_section(_), do: :all

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

  defp broadcast_record_processed(session_id, record) do
    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:record_processed,
       %{
         name: record.name_and_address,
         penalty_type: record.penalty_type,
         section: record.section_type
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
