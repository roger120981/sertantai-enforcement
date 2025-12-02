defmodule EhsEnforcement.Scraping.Agencies.Caa do
  @moduledoc """
  CAA-specific scraping implementation following the AgencyBehavior pattern.

  This module implements the AgencyBehavior callbacks for Civil Aviation Authority
  (CAA) enforcement scraping operations.

  ## CAA-Specific Characteristics

  - **Data sources**: PDF files (prosecutions) and HTML page (undertakings)
  - **Data types**: Prosecutions (Cases) AND Undertakings (Notices)
  - **Coverage**: UK aviation safety and consumer protection
  - **Volume**: ~6-10 prosecutions/year, ~34 undertakings (historical from 2007-2023)

  ## Data Types

  - **Prosecutions** → Cases: Court convictions for aviation safety offences
  - **Undertakings** → Notices: Enterprise Act 2002 Part 8 consumer commitments

  ## Legal Basis

  - Civil Aviation Act 1982
  - Air Navigation Order 2016
  - EU Regulation 261/2004 (retained as UK261)
  - Enterprise Act 2002 Part 8
  - Consumer Rights Act 2015
  """

  @behaviour EhsEnforcement.Scraping.AgencyBehavior

  require Logger

  alias EhsEnforcement.Scraping.ProcessingLog
  alias EhsEnforcement.Scraping.ScrapeSession
  alias EhsEnforcement.Scraping.Caa.CaaProsecutionScraper
  alias EhsEnforcement.Scraping.Caa.CaaProsecutionProcessor
  alias EhsEnforcement.Scraping.Caa.CaaUndertakingScraper
  alias EhsEnforcement.Scraping.Caa.CaaNoticeProcessor
  alias EhsEnforcement.Scraping.Caa.CaaAiCaseProcessor

  @impl true
  def validate_params(opts) do
    Logger.debug("CAA: Validating parameters: #{inspect(opts)}")

    # CAA-specific parameters
    data_type = Keyword.get(opts, :data_type, :all)
    years = Keyword.get(opts, :years)
    actor = Keyword.get(opts, :actor)
    scrape_type = Keyword.get(opts, :scrape_type, :manual)
    # AI parsing option for legacy format PDFs (2017-2022)
    use_ai_parsing = Keyword.get(opts, :use_ai_parsing, false)

    # Validate data_type
    valid_data_types = [:all, :prosecutions, :undertakings]

    if data_type not in valid_data_types do
      {:error,
       "Invalid data_type: #{inspect(data_type)}. Valid types: #{inspect(valid_data_types)}"}
    else
      validated_params = %{
        data_type: data_type,
        years: years,
        actor: actor,
        scrape_type: scrape_type,
        use_ai_parsing: use_ai_parsing
      }

      Logger.debug("CAA: Parameters validated successfully")
      {:ok, validated_params}
    end
  end

  @impl true
  def start_scraping(validated_params, _config) do
    Logger.info("CAA: Starting scraping session",
      data_type: validated_params.data_type,
      years: validated_params.years
    )

    # Create Ash ScrapeSession record
    session_id = EhsEnforcement.Scraping.AgencyBehavior.generate_session_id()

    # Estimate max_pages based on data type
    max_pages = estimate_max_pages(validated_params)

    ash_session_params = %{
      session_id: session_id,
      agency: :caa,
      start_page: 1,
      max_pages: max_pages,
      database: data_type_to_database(validated_params.data_type),
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
        Logger.metadata(session_id: session.session_id, agency: :caa)
        Logger.info("CAA: Created scraping session #{session.session_id}")

        # Store validated_params in session for execution
        session_with_params = Map.put(session, :validated_params, validated_params)

        # Execute the CAA scraping workflow
        execute_caa_scraping_session(session_with_params)

      {:error, reason} ->
        Logger.error("CAA: Failed to create ScrapeSession record: #{inspect(reason)}")
        {:error, "Failed to create CAA scraping session: #{inspect(reason)}"}
    end
  end

  @impl true
  def process_results(session_results) do
    Logger.info("CAA: Processing scraping results",
      session_id: session_results.session_id,
      status: session_results.status,
      cases_created: session_results.cases_created
    )

    session_results
  end

  # Public convenience functions for direct scraping

  @doc """
  Scrape all CAA data (prosecutions and undertakings).

  Options:
  - :years - List of fiscal years to scrape for prosecutions (e.g., ["2024-2025", "2023-2024"])
  - :actor - Actor for Ash operations
  - :use_ai_parsing - Use AI to parse legacy format PDFs (2017-2022). Default: false
  """
  def scrape_all(opts \\ []) do
    with {:ok, validated_params} <- validate_params(Keyword.put(opts, :data_type, :all)) do
      start_scraping(validated_params, %{})
    end
  end

  @doc """
  Scrape only CAA prosecutions from PDF reports.

  Options:
  - :years - List of fiscal years to scrape (default: all available 2017-2025)
  - :actor - Actor for Ash operations
  - :use_ai_parsing - Use AI to parse legacy format PDFs (2017-2022). Default: false
  """
  def scrape_prosecutions(opts \\ []) do
    with {:ok, validated_params} <- validate_params(Keyword.put(opts, :data_type, :prosecutions)) do
      start_scraping(validated_params, %{})
    end
  end

  @doc """
  Scrape only CAA undertakings from HTML page.

  Options:
  - :actor - Actor for Ash operations
  """
  def scrape_undertakings(opts \\ []) do
    with {:ok, validated_params} <- validate_params(Keyword.put(opts, :data_type, :undertakings)) do
      start_scraping(validated_params, %{})
    end
  end

  @doc """
  Scrape legacy format prosecution years using AI parsing.

  This is a convenience function that scrapes all legacy format years (2017-2022)
  using the AI parser. Requires AI client to be configured.

  Options:
  - :actor - Actor for Ash operations
  """
  def scrape_legacy_prosecutions_with_ai(opts \\ []) do
    if not CaaProsecutionScraper.ai_parsing_available?() do
      {:error, "AI parsing not available - check AI client configuration"}
    else
      opts =
        opts
        |> Keyword.put(:data_type, :prosecutions)
        |> Keyword.put(:years, CaaProsecutionScraper.legacy_format_years())
        |> Keyword.put(:use_ai_parsing, true)

      with {:ok, validated_params} <- validate_params(opts) do
        start_scraping(validated_params, %{})
      end
    end
  end

  @doc """
  Check if AI parsing is available for legacy format PDFs.
  """
  def ai_parsing_available? do
    CaaProsecutionScraper.ai_parsing_available?()
  end

  # Private functions for CAA-specific implementation

  defp estimate_max_pages(validated_params) do
    case validated_params.data_type do
      # 8 PDF files (one per fiscal year)
      :prosecutions -> length(validated_params.years || CaaProsecutionScraper.available_years())
      # Single HTML page
      :undertakings -> 1
      # All prosecutions + undertakings page
      :all -> length(validated_params.years || CaaProsecutionScraper.available_years()) + 1
    end
  end

  defp data_type_to_database(:prosecutions), do: "prosecutions"
  defp data_type_to_database(:undertakings), do: "undertakings"
  defp data_type_to_database(:all), do: "all"

  defp execute_caa_scraping_session(session) do
    Logger.info("CAA: Starting execution of scraping session: #{session.session_id}")

    validated_params = Map.get(session, :validated_params, %{})

    case validated_params.data_type do
      :prosecutions ->
        scrape_and_process_prosecutions(session)
        |> finalize_session()

      :undertakings ->
        scrape_and_process_undertakings(session)
        |> finalize_session()

      :all ->
        session
        |> scrape_and_process_prosecutions()
        |> scrape_and_process_undertakings()
        |> finalize_session()
    end
  end

  defp scrape_and_process_prosecutions(session) do
    Logger.info("CAA: Scraping prosecutions from PDF reports")

    validated_params = Map.get(session, :validated_params, %{})
    use_ai_parsing = Map.get(validated_params, :use_ai_parsing, false)
    requested_years = validated_params.years || CaaProsecutionScraper.available_years()

    if use_ai_parsing do
      scrape_prosecutions_with_ai_support(session, requested_years, validated_params)
    else
      scrape_prosecutions_standard(session, requested_years)
    end
  end

  # Standard scraping (modern format only, legacy returns empty)
  defp scrape_prosecutions_standard(session, years) do
    scrape_opts = [years: years]

    # scrape_all/1 always returns {:ok, prosecutions}
    {:ok, scraped_prosecutions} = CaaProsecutionScraper.scrape_all(scrape_opts)
    Logger.info("CAA: Scraped #{length(scraped_prosecutions)} prosecutions (standard parser)")

    # Update session with found count
    session =
      update_session(session, %{
        cases_found: session.cases_found + length(scraped_prosecutions)
      })

    # Process and create prosecutions
    process_prosecutions_serially(session, scraped_prosecutions)
  end

  # AI-enhanced scraping (handles both modern and legacy formats)
  defp scrape_prosecutions_with_ai_support(session, years, validated_params) do
    Logger.info("CAA: Using AI-enhanced scraping for #{length(years)} years")

    actor = Map.get(validated_params, :actor)

    # Split years into modern (regex) and legacy (AI) groups
    {modern_years, legacy_years} =
      Enum.split_with(years, fn year ->
        year in CaaProsecutionScraper.modern_format_years()
      end)

    # Process modern format years with standard parser
    session =
      if length(modern_years) > 0 do
        Logger.info(
          "CAA: Processing #{length(modern_years)} modern format years with regex parser"
        )

        scrape_prosecutions_standard(session, modern_years)
      else
        session
      end

    # Process legacy format years with AI parser
    if length(legacy_years) > 0 do
      Logger.info("CAA: Processing #{length(legacy_years)} legacy format years with AI parser")
      scrape_legacy_years_with_ai(session, legacy_years, actor)
    else
      session
    end
  end

  # Scrape legacy years using AI parser
  defp scrape_legacy_years_with_ai(session, years, actor) do
    Enum.reduce(years, session, fn year, current_session ->
      Logger.info("CAA: AI parsing legacy year #{year}")

      case CaaProsecutionScraper.scrape_legacy_year_with_ai(year) do
        {:ok, parsed_prosecutions} ->
          Logger.info(
            "CAA: AI extracted #{length(parsed_prosecutions)} prosecutions from #{year}"
          )

          # Update session with found count
          updated_session =
            update_session(current_session, %{
              cases_found: current_session.cases_found + length(parsed_prosecutions)
            })

          # Process AI-parsed prosecutions using the AI case processor
          process_ai_parsed_prosecutions(updated_session, parsed_prosecutions, actor)

        {:error, reason} ->
          Logger.error("CAA: Failed to AI parse year #{year}: #{inspect(reason)}")
          update_session(current_session, %{errors_count: current_session.errors_count + 1})
      end
    end)
  end

  # Process AI-parsed prosecutions using CaaAiCaseProcessor
  defp process_ai_parsed_prosecutions(session, parsed_prosecutions, actor) do
    Logger.info("CAA: Processing #{length(parsed_prosecutions)} AI-parsed prosecutions")

    # process_prosecutions/2 always returns {:ok, results}
    {:ok, results} = CaaAiCaseProcessor.process_prosecutions(parsed_prosecutions, actor)

    Logger.info(
      "CAA: AI processing complete - created: #{length(results.created)}, duplicates: #{length(results.duplicates)}, errors: #{length(results.errors)}"
    )

    # Update session counters
    updated_session =
      update_session(session, %{
        cases_processed: session.cases_processed + length(parsed_prosecutions),
        cases_created: session.cases_created + length(results.created),
        cases_exist_total: session.cases_exist_total + length(results.duplicates),
        errors_count: session.errors_count + length(results.errors)
      })

    # Create processing log for AI-parsed prosecutions
    create_ai_processing_log(updated_session, results, parsed_prosecutions)

    updated_session
  end

  defp scrape_and_process_undertakings(session) do
    Logger.info("CAA: Scraping undertakings from HTML page")

    case CaaUndertakingScraper.scrape_all() do
      {:ok, scraped_undertakings} ->
        Logger.info("CAA: Scraped #{length(scraped_undertakings)} undertakings")

        # Update session with found count
        session =
          update_session(session, %{
            cases_found: session.cases_found + length(scraped_undertakings)
          })

        # Process and create undertakings as notices
        process_undertakings_serially(session, scraped_undertakings)

      {:error, reason} ->
        Logger.error("CAA: Failed to scrape undertakings: #{inspect(reason)}")
        update_session(session, %{errors_count: session.errors_count + 1})
    end
  end

  defp process_prosecutions_serially(session, prosecutions) do
    Logger.info("CAA: Processing #{length(prosecutions)} prosecutions serially")

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
      Enum.reduce(prosecutions, initial_state, fn prosecution, {current_session, acc} ->
        case CaaProsecutionProcessor.process_and_create_prosecution(prosecution, actor) do
          {:ok, created_case} when is_struct(created_case) ->
            Logger.debug("CAA: Created case: #{created_case.regulator_id}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_created: current_session.cases_created + 1
              })

            updated_acc = %{
              acc
              | created: acc.created + 1,
                processed_items: [prosecution | acc.processed_items]
            }

            {updated_session, updated_acc}

          {:ok, :duplicate} ->
            Logger.debug("CAA: Case already exists: #{prosecution.defendant}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_exist_total: current_session.cases_exist_total + 1
              })

            updated_acc = %{
              acc
              | existing: acc.existing + 1,
                processed_items: [prosecution | acc.processed_items]
            }

            {updated_session, updated_acc}

          {:error, %Ash.Error.Invalid{errors: errors}} ->
            if duplicate_error?(errors) do
              Logger.debug("CAA: Case already exists: #{prosecution.defendant}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  cases_exist_total: current_session.cases_exist_total + 1
                })

              updated_acc = %{
                acc
                | existing: acc.existing + 1,
                  processed_items: [prosecution | acc.processed_items]
              }

              {updated_session, updated_acc}
            else
              Logger.warning("CAA: Error creating case: #{inspect(errors)}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  errors_count: current_session.errors_count + 1
                })

              updated_acc = %{acc | errors: acc.errors + 1}

              {updated_session, updated_acc}
            end

          {:error, reason} ->
            Logger.warning("CAA: Error processing prosecution: #{inspect(reason)}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                errors_count: current_session.errors_count + 1
              })

            updated_acc = %{acc | errors: acc.errors + 1}

            {updated_session, updated_acc}
        end
      end)

    # Create processing log for prosecutions
    create_processing_log(final_session, results, :prosecutions)

    final_session
  end

  defp process_undertakings_serially(session, undertakings) do
    Logger.info("CAA: Processing #{length(undertakings)} undertakings serially")

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
      Enum.reduce(undertakings, initial_state, fn undertaking, {current_session, acc} ->
        case CaaNoticeProcessor.process_and_create_undertaking(undertaking, actor) do
          {:ok, created_notice} when is_struct(created_notice) ->
            Logger.debug("CAA: Created notice: #{undertaking.organisation}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_created: current_session.cases_created + 1
              })

            updated_acc = %{
              acc
              | created: acc.created + 1,
                processed_items: [undertaking | acc.processed_items]
            }

            {updated_session, updated_acc}

          {:ok, :duplicate} ->
            Logger.debug("CAA: Notice already exists: #{undertaking.organisation}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_exist_total: current_session.cases_exist_total + 1
              })

            updated_acc = %{
              acc
              | existing: acc.existing + 1,
                processed_items: [undertaking | acc.processed_items]
            }

            {updated_session, updated_acc}

          {:error, %Ash.Error.Invalid{errors: errors}} ->
            if duplicate_error?(errors) do
              Logger.debug("CAA: Notice already exists: #{undertaking.organisation}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  cases_exist_total: current_session.cases_exist_total + 1
                })

              updated_acc = %{
                acc
                | existing: acc.existing + 1,
                  processed_items: [undertaking | acc.processed_items]
              }

              {updated_session, updated_acc}
            else
              Logger.warning("CAA: Error creating notice: #{inspect(errors)}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  errors_count: current_session.errors_count + 1
                })

              updated_acc = %{acc | errors: acc.errors + 1}

              {updated_session, updated_acc}
            end

          {:error, reason} ->
            Logger.warning("CAA: Error processing undertaking: #{inspect(reason)}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                errors_count: current_session.errors_count + 1
              })

            updated_acc = %{acc | errors: acc.errors + 1}

            {updated_session, updated_acc}
        end
      end)

    # Create processing log for undertakings
    create_processing_log(final_session, results, :undertakings)

    final_session
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
        Logger.error("CAA: Failed to update session: #{inspect(reason)}")
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
        Logger.info("CAA: Session finalized",
          session_id: final_session.session_id,
          status: final_session.status,
          created: final_session.cases_created,
          existing: final_session.cases_exist_total,
          errors: final_session.errors_count
        )

        {:ok, final_session}

      {:error, reason} ->
        Logger.error("CAA: Failed to finalize session: #{inspect(reason)}")
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

  defp create_processing_log(session, results, data_type) do
    # Create summary for UI display
    item_summary =
      results.processed_items
      |> Enum.take(50)
      |> Enum.map(fn item ->
        case data_type do
          :prosecutions ->
            %{
              defendant: item.defendant,
              fiscal_year: item.fiscal_year,
              date: item.date,
              court: item.court,
              sentence: item.sentence
            }

          :undertakings ->
            %{
              organisation: item.organisation,
              date_provided: item.date_provided,
              legislation: item.legislation
            }
        end
      end)

    log_params = %{
      session_id: session.session_id,
      agency: :caa,
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
        Logger.debug("CAA: Created processing log for #{data_type}")

      {:error, reason} ->
        Logger.warning("CAA: Failed to create processing log: #{inspect(reason)}")
    end
  end

  # Create processing log for AI-parsed prosecutions
  defp create_ai_processing_log(session, results, parsed_prosecutions) do
    # Create summary for UI display from AI-parsed data
    item_summary =
      parsed_prosecutions
      |> Enum.take(50)
      |> Enum.map(fn parsed ->
        %{
          defendant: parsed.defendant_name,
          fiscal_year: parsed.fiscal_year,
          date: if(parsed.hearing_date, do: Date.to_string(parsed.hearing_date), else: nil),
          court: parsed.court_name,
          fine_amount:
            if(parsed.fine_amount, do: Decimal.to_string(parsed.fine_amount), else: nil),
          offence_description: parsed.offence_description,
          parsing_method: "ai"
        }
      end)

    log_params = %{
      session_id: session.session_id,
      agency: :caa,
      # Use batch 2 to distinguish from regex-parsed
      batch_or_page: 2,
      items_found: length(parsed_prosecutions),
      items_created: length(results.created),
      items_existing: length(results.duplicates),
      items_failed: length(results.errors),
      creation_errors: Enum.map(results.errors, fn {_parsed, reason} -> inspect(reason) end),
      scraped_items: item_summary
    }

    case Ash.create(ProcessingLog, log_params) do
      {:ok, _log} ->
        Logger.debug("CAA: Created processing log for AI-parsed prosecutions")

      {:error, reason} ->
        Logger.warning("CAA: Failed to create AI processing log: #{inspect(reason)}")
    end
  end
end
