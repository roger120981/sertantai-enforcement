defmodule EhsEnforcement.Scraping.Agencies.Nrw do
  @moduledoc """
  NRW-specific scraping implementation following the AgencyBehavior pattern.

  This module implements the AgencyBehavior callbacks for Natural Resources Wales
  (NRW) scraping operations.

  ## NRW-Specific Characteristics

  - **News-based scraping**: Data comes from press releases/news articles
  - **AI-powered parsing**: Uses LLM to extract structured data from unstructured text
  - **Multi-case articles**: Single article may contain multiple defendants
  - **Criminal prosecutions**: Court cases with fines (maps to Case resource)

  ## Data Types

  - Prosecutions: Court cases with fines, costs, surcharges
  - POCA Confiscations: Proceeds of Crime Act orders
  - (Future) Civil sanctions: FMP, VMP, Undertakings (maps to Notice resource)
  """

  @behaviour EhsEnforcement.Scraping.AgencyBehavior

  require Logger

  alias EhsEnforcement.Scraping.ProcessingLog
  alias EhsEnforcement.Scraping.ScrapeSession
  alias EhsEnforcement.Scraping.Nrw.NrwNewsScraper
  alias EhsEnforcement.Scraping.Nrw.NrwAiArticleParser
  alias EhsEnforcement.Scraping.Nrw.NrwCaseProcessor

  @impl true
  def validate_params(opts) do
    Logger.debug("NRW: Validating parameters: #{inspect(opts)}")

    # NRW-specific parameters
    limit = Keyword.get(opts, :limit, 20)
    actor = Keyword.get(opts, :actor)
    scrape_type = Keyword.get(opts, :scrape_type, :manual)

    # Validate limit
    if not is_integer(limit) or limit < 1 or limit > 100 do
      {:error, "Invalid limit: #{limit}. Must be between 1 and 100"}
    else
      validated_params = %{
        limit: limit,
        actor: actor,
        scrape_type: scrape_type
      }

      Logger.debug("NRW: Parameters validated successfully")
      {:ok, validated_params}
    end
  end

  @impl true
  def start_scraping(validated_params, _config) do
    Logger.info("NRW: Starting scraping session",
      limit: validated_params.limit
    )

    # Create Ash ScrapeSession record
    session_id = EhsEnforcement.Scraping.AgencyBehavior.generate_session_id()

    ash_session_params = %{
      session_id: session_id,
      agency: :nrw,
      start_page: 1,
      max_pages: 1,
      database: "cases",
      status: :running,
      current_page: 1,
      pages_processed: 0,
      cases_found: 0,
      cases_processed: 0,
      cases_created: 0,
      cases_exist_total: 0,
      errors_count: 0
    }

    case Ash.create(ScrapeSession, ash_session_params) do
      {:ok, session} ->
        Logger.metadata(session_id: session.session_id, agency: :nrw)
        Logger.info("NRW: Created scraping session #{session.session_id}")

        # Store validated_params in session for execution
        session_with_params = Map.put(session, :validated_params, validated_params)

        # Execute the NRW scraping workflow
        execute_nrw_scraping_session(session_with_params)

      {:error, reason} ->
        Logger.error("NRW: Failed to create ScrapeSession record: #{inspect(reason)}")
        {:error, "Failed to create NRW scraping session: #{inspect(reason)}"}
    end
  end

  @impl true
  def process_results(session_results) do
    Logger.info("NRW: Processing scraping results",
      session_id: session_results.session_id,
      status: session_results.status,
      cases_created: session_results.cases_created
    )

    session_results
  end

  # Private functions for NRW-specific implementation

  defp execute_nrw_scraping_session(session) do
    Logger.info("NRW: Starting execution of scraping session: #{session.session_id}")

    validated_params = Map.get(session, :validated_params, %{})
    limit = Map.get(validated_params, :limit, 20)

    # PHASE 1: Fetch enforcement article URLs
    case NrwNewsScraper.fetch_enforcement_article_urls(limit) do
      {:ok, urls} when urls != [] ->
        Logger.info("NRW: Found #{length(urls)} enforcement articles")

        # Update session with found count
        session = update_session(session, %{cases_found: length(urls)})

        # PHASE 2: Fetch and parse articles
        process_articles(session, urls)
        |> finalize_session()

      {:ok, []} ->
        Logger.warning("NRW: No enforcement articles found")

        session
        |> update_session(%{status: :completed, pages_processed: 1})
        |> finalize_session()

      {:error, reason} ->
        Logger.error("NRW: Failed to fetch article URLs: #{inspect(reason)}")

        session
        |> update_session(%{status: :failed, errors_count: session.errors_count + 1})
        |> finalize_session()
    end
  end

  defp process_articles(session, urls) do
    Logger.info("NRW: Processing #{length(urls)} articles")

    validated_params = Map.get(session, :validated_params, %{})
    actor = Map.get(validated_params, :actor)

    # Track results
    initial_state = {
      session,
      %{
        created: 0,
        existing: 0,
        errors: 0,
        processed_items: []
      }
    }

    {final_session, results} =
      Enum.reduce(urls, initial_state, fn url, {current_session, acc} ->
        # Fetch article
        case NrwNewsScraper.fetch_and_parse_article(url) do
          {:ok, article} ->
            # Parse with AI
            case NrwAiArticleParser.parse_article(article) do
              {:ok, parsed_cases} when parsed_cases != [] ->
                # Process each case from the article
                {session_after_cases, acc_after_cases} =
                  process_parsed_cases(current_session, acc, parsed_cases, actor)

                {session_after_cases, acc_after_cases}

              {:ok, []} ->
                Logger.info("NRW: No cases extracted from article: #{url}")

                updated_session =
                  update_session(current_session, %{
                    cases_processed: current_session.cases_processed + 1
                  })

                {updated_session, acc}

              {:error, reason} ->
                Logger.warning("NRW: Failed to parse article #{url}: #{inspect(reason)}")

                updated_session =
                  update_session(current_session, %{
                    cases_processed: current_session.cases_processed + 1,
                    errors_count: current_session.errors_count + 1
                  })

                {updated_session, %{acc | errors: acc.errors + 1}}
            end

          {:error, reason} ->
            Logger.warning("NRW: Failed to fetch article #{url}: #{inspect(reason)}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                errors_count: current_session.errors_count + 1
              })

            {updated_session, %{acc | errors: acc.errors + 1}}
        end
      end)

    # Create processing log
    create_processing_log(final_session, results)

    # Update pages_processed
    update_session(final_session, %{pages_processed: 1})
  end

  defp process_parsed_cases(session, acc, parsed_cases, actor) do
    Enum.reduce(parsed_cases, {session, acc}, fn parsed_case, {current_session, current_acc} ->
      case NrwCaseProcessor.process_and_create_case(parsed_case, actor) do
        {:ok, case_record} ->
          Logger.info("NRW: Created case: #{case_record.regulator_id}")

          updated_session =
            update_session(current_session, %{
              cases_processed: current_session.cases_processed + 1,
              cases_created: current_session.cases_created + 1
            })

          updated_acc = %{
            current_acc
            | created: current_acc.created + 1,
              processed_items: [parsed_case | current_acc.processed_items]
          }

          {updated_session, updated_acc}

        {:error, %Ash.Error.Invalid{errors: errors}} ->
          if duplicate_error?(errors) do
            Logger.info("NRW: Case already exists: #{parsed_case.offender_name}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_exist_total: current_session.cases_exist_total + 1
              })

            updated_acc = %{
              current_acc
              | existing: current_acc.existing + 1,
                processed_items: [parsed_case | current_acc.processed_items]
            }

            {updated_session, updated_acc}
          else
            Logger.warning("NRW: Error creating case: #{inspect(errors)}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                errors_count: current_session.errors_count + 1
              })

            updated_acc = %{current_acc | errors: current_acc.errors + 1}

            {updated_session, updated_acc}
          end

        {:error, reason} ->
          Logger.warning("NRW: Error processing case: #{inspect(reason)}")

          updated_session =
            update_session(current_session, %{
              cases_processed: current_session.cases_processed + 1,
              errors_count: current_session.errors_count + 1
            })

          updated_acc = %{current_acc | errors: current_acc.errors + 1}

          {updated_session, updated_acc}
      end
    end)
  end

  defp update_session(session, params) do
    validated_params = Map.get(session, :validated_params)

    case Ash.update(session, params) do
      {:ok, updated_session} ->
        if validated_params do
          Map.put(updated_session, :validated_params, validated_params)
        else
          updated_session
        end

      {:error, reason} ->
        Logger.error("NRW: Failed to update session: #{inspect(reason)}")
        session
    end
  end

  defp finalize_session(session) do
    final_status =
      cond do
        session.status == :failed -> :failed
        session.errors_count > 0 and session.cases_created == 0 -> :failed
        true -> :completed
      end

    case Ash.update(session, %{status: final_status}) do
      {:ok, final_session} ->
        Logger.info("NRW: Session finalized",
          session_id: final_session.session_id,
          status: final_session.status,
          created: final_session.cases_created,
          existing: final_session.cases_exist_total,
          errors: final_session.errors_count
        )

        {:ok, final_session}

      {:error, reason} ->
        Logger.error("NRW: Failed to finalize session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp duplicate_error?(errors) when is_list(errors) do
    Enum.any?(errors, fn error ->
      case error do
        %{message: message} when is_binary(message) ->
          String.contains?(message, "already exists") or
            String.contains?(message, "has already been taken")

        _ ->
          false
      end
    end)
  end

  defp duplicate_error?(_), do: false

  defp create_processing_log(session, results) do
    # Create summary for UI display
    item_summary =
      results.processed_items
      |> Enum.take(50)
      |> Enum.map(fn parsed_case ->
        %{
          name: parsed_case.offender_name,
          date: parsed_case.hearing_date,
          type: parsed_case.offender_type,
          amount:
            if(parsed_case.fine_amount,
              do: Decimal.to_string(parsed_case.fine_amount),
              else: nil
            )
        }
      end)

    log_params = %{
      session_id: session.session_id,
      agency: :nrw,
      batch_or_page: 1,
      items_found: length(results.processed_items),
      items_created: results.created,
      items_existing: results.existing,
      items_failed: results.errors,
      creation_errors: [],
      scraped_items: item_summary
    }

    case Ash.create(ProcessingLog, log_params) do
      {:ok, _log} ->
        Logger.debug("NRW: Created processing log")

      {:error, reason} ->
        Logger.warning("NRW: Failed to create processing log: #{inspect(reason)}")
    end
  end
end
