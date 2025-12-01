defmodule EhsEnforcement.Scraping.Agencies.Orr do
  @moduledoc """
  ORR-specific scraping implementation following the AgencyBehavior pattern.

  This module implements the AgencyBehavior callbacks for Office of Rail and Road
  (ORR) enforcement scraping operations.

  ## ORR-Specific Characteristics

  - **Data source**: ORR website (HTML pages)
  - **Data types**: Prosecutions (Cases) AND Notices (Improvement + Prohibition)
  - **Coverage**: Great Britain rail network
  - **Volume**: ~6 prosecutions/year, ~5-10 improvement notices/year, ~1-3 prohibition notices/year

  ## Data Types

  - **Prosecutions** → Cases: Court convictions for safety breaches
  - **Improvement Notices** → Notices: Required safety improvements with deadline
  - **Prohibition Notices** → Notices: Immediate prohibition of unsafe activities

  ## Legal Basis

  - Health and Safety at Work etc Act 1974
  - Railways and Other Guided Transport Systems (Safety) Regulations 2006
  """

  @behaviour EhsEnforcement.Scraping.AgencyBehavior

  require Logger

  alias EhsEnforcement.Scraping.ProcessingLog
  alias EhsEnforcement.Scraping.ScrapeSession
  alias EhsEnforcement.Scraping.Orr.OrrProsecutionScraper
  alias EhsEnforcement.Scraping.Orr.OrrProsecutionProcessor
  alias EhsEnforcement.Scraping.Orr.OrrNoticeScraper
  alias EhsEnforcement.Scraping.Orr.OrrNoticeProcessor

  @impl true
  def validate_params(opts) do
    Logger.debug("ORR: Validating parameters: #{inspect(opts)}")

    # ORR-specific parameters
    data_type = Keyword.get(opts, :data_type, :all)
    years = Keyword.get(opts, :years)
    notice_type = Keyword.get(opts, :notice_type)
    actor = Keyword.get(opts, :actor)
    scrape_type = Keyword.get(opts, :scrape_type, :manual)

    # Validate data_type
    valid_data_types = [:all, :prosecutions, :notices]

    if data_type not in valid_data_types do
      {:error,
       "Invalid data_type: #{inspect(data_type)}. Valid types: #{inspect(valid_data_types)}"}
    else
      # Validate notice_type if specified
      valid_notice_types = [:improvement, :prohibition, nil]

      if notice_type not in valid_notice_types do
        {:error,
         "Invalid notice_type: #{inspect(notice_type)}. Valid types: #{inspect(valid_notice_types)}"}
      else
        validated_params = %{
          data_type: data_type,
          years: years,
          notice_type: notice_type,
          actor: actor,
          scrape_type: scrape_type
        }

        Logger.debug("ORR: Parameters validated successfully")
        {:ok, validated_params}
      end
    end
  end

  @impl true
  def start_scraping(validated_params, _config) do
    Logger.info("ORR: Starting scraping session",
      data_type: validated_params.data_type,
      years: validated_params.years,
      notice_type: validated_params.notice_type
    )

    # Create Ash ScrapeSession record
    session_id = EhsEnforcement.Scraping.AgencyBehavior.generate_session_id()

    # Estimate max_pages based on data type
    max_pages = estimate_max_pages(validated_params)

    ash_session_params = %{
      session_id: session_id,
      agency: :orr,
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
        Logger.metadata(session_id: session.session_id, agency: :orr)
        Logger.info("ORR: Created scraping session #{session.session_id}")

        # Store validated_params in session for execution
        session_with_params = Map.put(session, :validated_params, validated_params)

        # Execute the ORR scraping workflow
        execute_orr_scraping_session(session_with_params)

      {:error, reason} ->
        Logger.error("ORR: Failed to create ScrapeSession record: #{inspect(reason)}")
        {:error, "Failed to create ORR scraping session: #{inspect(reason)}"}
    end
  end

  @impl true
  def process_results(session_results) do
    Logger.info("ORR: Processing scraping results",
      session_id: session_results.session_id,
      status: session_results.status,
      cases_created: session_results.cases_created
    )

    session_results
  end

  # Public convenience functions for direct scraping

  @doc """
  Scrape all ORR data (prosecutions and notices).

  Options:
  - :years - List of years to scrape
  - :actor - Actor for Ash operations
  """
  def scrape_all(opts \\ []) do
    with {:ok, validated_params} <- validate_params(Keyword.put(opts, :data_type, :all)) do
      start_scraping(validated_params, %{})
    end
  end

  @doc """
  Scrape only ORR prosecutions.

  Options:
  - :years - List of years to scrape (default: all available)
  - :actor - Actor for Ash operations
  """
  def scrape_prosecutions(opts \\ []) do
    with {:ok, validated_params} <- validate_params(Keyword.put(opts, :data_type, :prosecutions)) do
      start_scraping(validated_params, %{})
    end
  end

  @doc """
  Scrape only ORR notices.

  Options:
  - :years - List of years to scrape
  - :notice_type - :improvement, :prohibition, or nil (both)
  - :actor - Actor for Ash operations
  """
  def scrape_notices(opts \\ []) do
    with {:ok, validated_params} <- validate_params(Keyword.put(opts, :data_type, :notices)) do
      start_scraping(validated_params, %{})
    end
  end

  # Private functions for ORR-specific implementation

  defp estimate_max_pages(validated_params) do
    case validated_params.data_type do
      :prosecutions -> 1
      :notices -> length(validated_params.years || OrrNoticeScraper.improvement_years()) * 2
      :all -> 1 + length(validated_params.years || OrrNoticeScraper.improvement_years()) * 2
    end
  end

  defp data_type_to_database(:prosecutions), do: "prosecutions"
  defp data_type_to_database(:notices), do: "notices"
  defp data_type_to_database(:all), do: "all"

  defp execute_orr_scraping_session(session) do
    Logger.info("ORR: Starting execution of scraping session: #{session.session_id}")

    validated_params = Map.get(session, :validated_params, %{})

    case validated_params.data_type do
      :prosecutions ->
        scrape_and_process_prosecutions(session)
        |> finalize_session()

      :notices ->
        scrape_and_process_notices(session)
        |> finalize_session()

      :all ->
        session
        |> scrape_and_process_prosecutions()
        |> scrape_and_process_notices()
        |> finalize_session()
    end
  end

  defp scrape_and_process_prosecutions(session) do
    Logger.info("ORR: Scraping prosecutions")

    validated_params = Map.get(session, :validated_params, %{})

    scrape_opts =
      if validated_params.years do
        [years: validated_params.years]
      else
        []
      end

    case OrrProsecutionScraper.scrape_all(scrape_opts) do
      {:ok, scraped_prosecutions} ->
        Logger.info("ORR: Scraped #{length(scraped_prosecutions)} prosecutions")

        # Update session with found count
        session =
          update_session(session, %{
            cases_found: session.cases_found + length(scraped_prosecutions)
          })

        # Process and create prosecutions
        process_prosecutions_serially(session, scraped_prosecutions)

      {:error, reason} ->
        Logger.error("ORR: Failed to scrape prosecutions: #{inspect(reason)}")
        update_session(session, %{errors_count: session.errors_count + 1})
    end
  end

  defp scrape_and_process_notices(session) do
    Logger.info("ORR: Scraping notices")

    validated_params = Map.get(session, :validated_params, %{})

    scrape_opts = []

    scrape_opts =
      if validated_params.years,
        do: Keyword.put(scrape_opts, :years, validated_params.years),
        else: scrape_opts

    scrape_opts =
      if validated_params.notice_type,
        do: Keyword.put(scrape_opts, :notice_type, validated_params.notice_type),
        else: scrape_opts

    # OrrNoticeScraper.scrape_all always returns {:ok, notices}
    {:ok, scraped_notices} = OrrNoticeScraper.scrape_all(scrape_opts)

    Logger.info("ORR: Scraped #{length(scraped_notices)} notices")

    # Update session with found count
    session =
      update_session(session, %{cases_found: session.cases_found + length(scraped_notices)})

    # Process and create notices
    process_notices_serially(session, scraped_notices)
  end

  defp process_prosecutions_serially(session, prosecutions) do
    Logger.info("ORR: Processing #{length(prosecutions)} prosecutions serially")

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
        case OrrProsecutionProcessor.process_and_create_prosecution(prosecution, actor) do
          {:ok, created_case} when is_struct(created_case) ->
            Logger.debug("ORR: Created case: #{created_case.regulator_id}")

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
            Logger.debug("ORR: Case already exists: #{prosecution.company}")

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
              Logger.debug("ORR: Case already exists: #{prosecution.company}")

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
              Logger.warning("ORR: Error creating case: #{inspect(errors)}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  errors_count: current_session.errors_count + 1
                })

              updated_acc = %{acc | errors: acc.errors + 1}

              {updated_session, updated_acc}
            end

          {:error, reason} ->
            Logger.warning("ORR: Error processing prosecution: #{inspect(reason)}")

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

  defp process_notices_serially(session, notices) do
    Logger.info("ORR: Processing #{length(notices)} notices serially")

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
      Enum.reduce(notices, initial_state, fn notice, {current_session, acc} ->
        case OrrNoticeProcessor.process_and_create_notice(notice, actor) do
          {:ok, created_notice} when is_struct(created_notice) ->
            Logger.debug("ORR: Created notice: #{notice.reference || notice.company}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_created: current_session.cases_created + 1
              })

            updated_acc = %{
              acc
              | created: acc.created + 1,
                processed_items: [notice | acc.processed_items]
            }

            {updated_session, updated_acc}

          {:ok, :duplicate} ->
            Logger.debug("ORR: Notice already exists: #{notice.reference || notice.company}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                cases_exist_total: current_session.cases_exist_total + 1
              })

            updated_acc = %{
              acc
              | existing: acc.existing + 1,
                processed_items: [notice | acc.processed_items]
            }

            {updated_session, updated_acc}

          {:error, %Ash.Error.Invalid{errors: errors}} ->
            if duplicate_error?(errors) do
              Logger.debug("ORR: Notice already exists: #{notice.reference || notice.company}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  cases_exist_total: current_session.cases_exist_total + 1
                })

              updated_acc = %{
                acc
                | existing: acc.existing + 1,
                  processed_items: [notice | acc.processed_items]
              }

              {updated_session, updated_acc}
            else
              Logger.warning("ORR: Error creating notice: #{inspect(errors)}")

              updated_session =
                update_session(current_session, %{
                  cases_processed: current_session.cases_processed + 1,
                  errors_count: current_session.errors_count + 1
                })

              updated_acc = %{acc | errors: acc.errors + 1}

              {updated_session, updated_acc}
            end

          {:error, reason} ->
            Logger.warning("ORR: Error processing notice: #{inspect(reason)}")

            updated_session =
              update_session(current_session, %{
                cases_processed: current_session.cases_processed + 1,
                errors_count: current_session.errors_count + 1
              })

            updated_acc = %{acc | errors: acc.errors + 1}

            {updated_session, updated_acc}
        end
      end)

    # Create processing log for notices
    create_processing_log(final_session, results, :notices)

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
        Logger.error("ORR: Failed to update session: #{inspect(reason)}")
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
        Logger.info("ORR: Session finalized",
          session_id: final_session.session_id,
          status: final_session.status,
          created: final_session.cases_created,
          existing: final_session.cases_exist_total,
          errors: final_session.errors_count
        )

        {:ok, final_session}

      {:error, reason} ->
        Logger.error("ORR: Failed to finalize session: #{inspect(reason)}")
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
              company: item.company,
              year: item.year,
              sentencing_date: item.sentencing_date,
              court: item.court,
              penalty: item.penalty
            }

          :notices ->
            %{
              company: item.company,
              year: item.year,
              reference: item.reference,
              notice_type: item.notice_type,
              status: item.status
            }
        end
      end)

    log_params = %{
      session_id: session.session_id,
      agency: :orr,
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
        Logger.debug("ORR: Created processing log for #{data_type}")

      {:error, reason} ->
        Logger.warning("ORR: Failed to create processing log: #{inspect(reason)}")
    end
  end
end
