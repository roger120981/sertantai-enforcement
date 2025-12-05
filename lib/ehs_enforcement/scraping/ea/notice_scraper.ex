defmodule EhsEnforcement.Scraping.Ea.NoticeScraper do
  @moduledoc """
  EA Notice Scraper - Thin wrapper around EA CaseScraper for enforcement notices.

  This module provides notice-specific scraping functionality by filtering
  EA enforcement action searches to `:enforcement_notice` action types only.
  It reuses all existing EA case scraping infrastructure while providing
  a focused interface for notice collection.

  ## Key Characteristics

  - **Action Type Filtering**: Only retrieves `:enforcement_notice` action types
  - **Wrapper Pattern**: Delegates to CaseScraper with notice-specific filters
  - **Consistent Interface**: Mirrors HSE notice scraper patterns
  - **Date Range Support**: Uses same date-based filtering as EA case scraping

  ## Usage

      # Collect notice summary records for date range
      {:ok, notices} = NoticeScraper.collect_summary_records(
        ~D[2024-01-01],
        ~D[2024-12-31],
        timeout_ms: 30_000
      )

      # Fetch detailed notice record
      {:ok, detail} = NoticeScraper.fetch_detail_record(notice_summary, timeout_ms: 30_000)
  """

  require Logger
  alias EhsEnforcement.Scraping.Ea.CaseScraper

  @doc """
  Collect summary records for EA enforcement notices within a date range.

  This function wraps CaseScraper.collect_summary_records_for_action_type/4
  with `:enforcement_notice` as the fixed action type.

  ## Parameters

  - `date_from` - Start date for notice search (Date struct)
  - `date_to` - End date for notice search (Date struct)
  - `opts` - Options passed to underlying case scraper

  ## Returns

  - `{:ok, summary_records}` - List of EaDetailRecord structs for notices
  - `{:error, reason}` - Error during scraping

  ## Examples

      # Get all enforcement notices for 2024
      {:ok, notices} = NoticeScraper.collect_summary_records(
        ~D[2024-01-01],
        ~D[2024-12-31]
      )

      # With custom timeout
      {:ok, notices} = NoticeScraper.collect_summary_records(
        ~D[2024-01-01],
        ~D[2024-12-31],
        timeout_ms: 45_000
      )
  """
  def collect_summary_records(date_from, date_to, opts \\ []) do
    Logger.debug("EA NoticeScraper: Collecting summary records for enforcement notices",
      date_from: date_from,
      date_to: date_to
    )

    # Use CaseScraper with enforcement_notice action type filter
    case CaseScraper.collect_summary_records_for_action_type(
           date_from,
           date_to,
           # Fixed action type for notices
           :enforcement_notice,
           opts
         ) do
      {:ok, summary_records} ->
        Logger.info(
          "EA NoticeScraper: Found #{length(summary_records)} enforcement notice summaries"
        )

        {:ok, summary_records}

      {:error, reason} ->
        Logger.error("EA NoticeScraper: Failed to collect notice summaries: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch detailed record for a specific EA enforcement notice.

  This function wraps CaseScraper.fetch_detail_record_individual/2
  to retrieve full notice details from an EA summary record.

  ## Parameters

  - `summary_record` - EaDetailRecord struct from collect_summary_records/3
  - `opts` - Options for detail fetching (timeout_ms, detail_delay_ms)

  ## Returns

  - `{:ok, detail_record}` - Enriched EaDetailRecord with full notice details
  - `{:error, reason}` - Error during detail fetching

  ## Examples

      # Fetch notice details with default settings
      {:ok, detail} = NoticeScraper.fetch_detail_record(notice_summary)

      # With custom timeout and delay
      {:ok, detail} = NoticeScraper.fetch_detail_record(
        notice_summary,
        timeout_ms: 30_000,
        detail_delay_ms: 2_000
      )
  """
  def fetch_detail_record(summary_record, opts \\ []) do
    Logger.debug(
      "EA NoticeScraper: Fetching detail record for notice: #{summary_record.ea_record_id}"
    )

    case CaseScraper.fetch_detail_record_individual(summary_record, opts) do
      {:ok, detail_record} ->
        Logger.debug(
          "EA NoticeScraper: Successfully fetched notice details for: #{detail_record.ea_record_id}"
        )

        {:ok, detail_record}

      {:error, reason} ->
        Logger.warning(
          "EA NoticeScraper: Failed to fetch notice details for #{summary_record.ea_record_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Helper function to check if a scraped record is actually an enforcement notice.

  This provides additional validation that the record returned by EA
  is indeed an enforcement notice, since EA's filtering is not always perfect.

  ## Parameters

  - `detail_record` - EaDetailRecord struct with full details

  ## Returns

  - `true` if record represents an enforcement notice
  - `false` if record is a different action type

  ## Examples

      if NoticeScraper.enforcement_notice?(detail_record) do
        # Process as notice
      else
        Logger.warning("Expected notice but got different action type")
      end
  """
  def enforcement_notice?(detail_record) do
    # Check if the action type matches enforcement notice
    action_type = Map.get(detail_record, :action_type)

    case action_type do
      :enforcement_notice -> true
      "enforcement_notice" -> true
      s when is_binary(s) -> String.contains?(String.downcase(s), ["enforcement", "notice"])
      _ -> false
    end
  end

  @doc """
  Batch collect and enrich notice records for a date range.

  This is a convenience function that combines summary collection
  and detail fetching into a single operation.

  ## Parameters

  - `date_from` - Start date for notice search
  - `date_to` - End date for notice search
  - `opts` - Options for scraping (timeout_ms, detail_delay_ms, batch_size)

  ## Returns

  - `{:ok, enriched_records}` - List of detailed notice records
  - `{:error, reason}` - Error during batch processing

  ## Examples

      # Get all detailed notices for Q1 2024
      {:ok, notices} = NoticeScraper.collect_and_enrich_notices(
        ~D[2024-01-01],
        ~D[2024-03-31]
      )
  """
  def collect_and_enrich_notices(date_from, date_to, opts \\ []) do
    Logger.info("EA NoticeScraper: Starting batch collection and enrichment",
      date_from: date_from,
      date_to: date_to
    )

    with {:ok, summary_records} <- collect_summary_records(date_from, date_to, opts),
         {:ok, enriched_records} <- enrich_notice_batch(summary_records, opts) do
      Logger.info(
        "EA NoticeScraper: Successfully enriched #{length(enriched_records)} notice records"
      )

      {:ok, enriched_records}
    else
      {:error, reason} ->
        Logger.error("EA NoticeScraper: Batch collection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helper to enrich a batch of notice summary records
  defp enrich_notice_batch(summary_records, opts) do
    Logger.debug("EA NoticeScraper: Enriching #{length(summary_records)} notice summaries")

    detail_delay_ms = Keyword.get(opts, :detail_delay_ms, 2_000)

    enriched_records =
      Enum.reduce(summary_records, [], fn summary, acc ->
        # Add delay between requests for respectful scraping
        if length(acc) > 0, do: Process.sleep(detail_delay_ms)

        case fetch_detail_record(summary, opts) do
          {:ok, detail_record} ->
            # Validate this is actually a notice
            if enforcement_notice?(detail_record) do
              [detail_record | acc]
            else
              Logger.warning(
                "EA NoticeScraper: Skipping non-notice record: #{detail_record.ea_record_id}"
              )

              acc
            end

          {:error, reason} ->
            Logger.warning(
              "EA NoticeScraper: Failed to enrich #{summary.ea_record_id}: #{inspect(reason)}"
            )

            acc
        end
      end)

    {:ok, Enum.reverse(enriched_records)}
  end
end
