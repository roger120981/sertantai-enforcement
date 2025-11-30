defmodule EhsEnforcement.Scraping.Api.NrwCoordinator do
  @moduledoc """
  Direct coordinator for NRW case scraping via API.

  NRW publishes enforcement data through news articles, which requires:
  1. Fetching article URLs from news listing page
  2. Parsing each article with AI to extract structured case data
  3. Creating Case records for each defendant

  Implements workflow:
  1. Scrape news listing → Get enforcement article URLs
  2. Fetch each article → Parse with AI
  3. Filter against DB → Identify new/existing
  4. Process and save → Create Case records
  5. Broadcast progress → SSE streaming to frontend
  """

  require Logger
  require Ash.Query

  alias EhsEnforcement.Scraping.Nrw.{NrwNewsScraper, NrwAiArticleParser, NrwCaseProcessor}
  alias EhsEnforcement.Enforcement.Case
  alias Phoenix.PubSub

  @doc """
  Scrape NRW cases with full workflow.

  ## Parameters
    - session_id: UUID for this scraping session
    - limit: Maximum number of articles to process (default 20)
    - actor: User performing the scraping (for Ash authorization)

  ## Returns
    - {:ok, %{created: count, updated: count}}
    - {:error, reason}
  """
  def scrape_batch(session_id, limit \\ 20, actor \\ nil) do
    Logger.info("Starting NRW case scraping",
      session_id: session_id,
      limit: limit
    )

    try do
      # PHASE 1: Fetch enforcement article URLs
      _ =
        broadcast_progress(session_id, %{
          phase: "scraping_page",
          message: "Fetching NRW news articles..."
        })

      article_urls = fetch_article_urls(session_id, limit)

      if Enum.empty?(article_urls) do
        _ =
          broadcast_completed(session_id, %{
            records_found: 0,
            records_existing: 0,
            records_created: 0,
            records_updated: 0
          })

        {:ok, %{created: 0, updated: 0}}
      else
        Logger.info("Phase 1 complete: Found #{length(article_urls)} article URLs")

        # PHASE 2: Fetch and parse articles with AI
        _ =
          broadcast_progress(session_id, %{
            phase: "parsing",
            articles_found: length(article_urls),
            message: "Parsing articles with AI..."
          })

        parsed_cases = fetch_and_parse_articles(session_id, article_urls)

        Logger.info("Phase 2 complete: Extracted #{length(parsed_cases)} cases from articles")

        # PHASE 3: Filter against existing DB records
        _ =
          broadcast_progress(session_id, %{
            phase: "filtering",
            records_found: length(parsed_cases)
          })

        {new_records, existing_records} = filter_against_db(parsed_cases)

        _ =
          broadcast_progress(session_id, %{
            phase: "filtering",
            records_to_process: length(new_records),
            records_existing: length(existing_records)
          })

        Logger.info(
          "Phase 3 complete: #{length(new_records)} new, #{length(existing_records)} existing"
        )

        # PHASE 4: Process and save records one-by-one (real-time progress)
        _ =
          broadcast_progress(session_id, %{
            phase: "processing_records",
            records_to_process: length(new_records)
          })

        {created_count, updated_count} =
          process_and_save_cases(session_id, new_records, actor)

        Logger.info("Phase 4 complete: Created #{created_count}, Updated #{updated_count}")

        # Broadcast completion
        _ =
          broadcast_completed(session_id, %{
            records_found: length(parsed_cases),
            records_existing: length(existing_records),
            records_created: created_count,
            records_updated: updated_count
          })

        {:ok, %{created: created_count, updated: updated_count}}
      end
    rescue
      error ->
        Logger.error("NRW case scraping failed: #{inspect(error)}")
        _ = broadcast_error(session_id, %{message: "Scraping failed: #{inspect(error)}"})
        {:error, error}
    end
  end

  # ============================================================================
  # PHASE 1: Fetch Article URLs
  # ============================================================================

  defp fetch_article_urls(session_id, limit) do
    case NrwNewsScraper.fetch_enforcement_article_urls(limit) do
      {:ok, urls} ->
        _ =
          broadcast_progress(session_id, %{
            phase: "scraping_page",
            articles_found: length(urls)
          })

        urls

      {:error, reason} ->
        Logger.warning("NRW URL fetch failed: #{inspect(reason)}")
        _ = broadcast_error(session_id, %{message: "URL fetch error: #{inspect(reason)}"})
        []
    end
  end

  # ============================================================================
  # PHASE 2: Fetch and Parse Articles with AI
  # ============================================================================

  defp fetch_and_parse_articles(session_id, urls) do
    urls
    |> Enum.with_index()
    |> Enum.flat_map(fn {url, index} ->
      _ =
        broadcast_progress(session_id, %{
          phase: "parsing",
          current_article: index + 1,
          total_articles: length(urls),
          message: "Parsing article #{index + 1} of #{length(urls)}..."
        })

      case NrwNewsScraper.fetch_and_parse_article(url) do
        {:ok, article} ->
          case NrwAiArticleParser.parse_article(article) do
            {:ok, parsed_cases} ->
              Logger.debug("NRW: Extracted #{length(parsed_cases)} cases from #{url}")
              parsed_cases

            {:error, reason} ->
              Logger.warning("NRW: AI parsing failed for #{url}: #{inspect(reason)}")
              _ = broadcast_error(session_id, %{url: url, message: "AI parsing failed"})
              []
          end

        {:error, reason} ->
          Logger.warning("NRW: Failed to fetch article #{url}: #{inspect(reason)}")
          _ = broadcast_error(session_id, %{url: url, message: "Fetch failed"})
          []
      end
    end)
  end

  # ============================================================================
  # PHASE 3: Filter Against DB (Single Batch Query)
  # ============================================================================

  defp filter_against_db(parsed_cases) do
    # Process all parsed cases to get regulator_ids
    processed_with_ids =
      parsed_cases
      |> Enum.map(fn parsed_case ->
        case NrwCaseProcessor.process_case(parsed_case) do
          {:ok, processed} -> {parsed_case, processed.regulator_id}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    regulator_ids = Enum.map(processed_with_ids, fn {_case, id} -> id end)

    # Single batch query for all existing cases
    existing_map =
      Case
      |> Ash.Query.filter(regulator_id in ^regulator_ids)
      |> Ash.read!()
      |> Map.new(&{&1.regulator_id, &1})

    # Categorize: new or existing
    Enum.reduce(processed_with_ids, {[], []}, fn {parsed_case, regulator_id}, {new, existing} ->
      case Map.get(existing_map, regulator_id) do
        nil ->
          # New record
          {[parsed_case | new], existing}

        _existing_case ->
          # Already exists
          {new, [parsed_case | existing]}
      end
    end)
  end

  # ============================================================================
  # PHASE 4: Process and Save Records One-by-One (Real-time Progress)
  # ============================================================================

  defp process_and_save_cases(session_id, cases_to_process, actor) do
    cases_to_process
    |> Enum.with_index()
    |> Enum.reduce({0, 0}, fn {parsed_case, index}, {created, updated} ->
      # Process and save using processor
      {new_created, new_updated} =
        case NrwCaseProcessor.process_and_create_case(parsed_case, actor) do
          {:ok, _case} ->
            # Successfully saved
            {created + 1, updated}

          {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.InvalidAttribute{} | _]}} ->
            # Likely a duplicate - count as existing
            {created, updated}

          {:error, reason} ->
            Logger.warning("Failed to save NRW case: #{inspect(reason)}")

            _ =
              broadcast_error(session_id, %{
                name: parsed_case.offender_name,
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
      _ = broadcast_record_processed(session_id, parsed_case)

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

  defp broadcast_record_processed(session_id, parsed_case) do
    PubSub.broadcast(
      EhsEnforcement.PubSub,
      "scrape_session:#{session_id}",
      {:record_processed,
       %{
         name: parsed_case.offender_name,
         offender_type: parsed_case.offender_type,
         fine: parsed_case.fine_amount
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
