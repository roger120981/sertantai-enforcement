defmodule EhsEnforcement.Scraping.Agencies.Opss do
  @moduledoc """
  OPSS-specific scraping implementation following the AgencyBehavior pattern.

  This module implements the AgencyBehavior callbacks for Office for Product
  Safety and Standards (OPSS) scraping operations.

  ## OPSS-Specific Characteristics

  - **Single data source**: GOV.UK enforcement actions publications
  - **HTML scraping**: Bi-annual enforcement reports (2022+)
  - **Mixed actions**: Both notices and prosecutions in same reports
  - **Categories**: Product Safety, Construction, Ecodesign, Timber

  ## Notice Types

  - Compliance Notice - requires corrective action
  - Stop Notice - prohibits placing on market
  - Prohibition Notice - prohibits supply
  - Withdrawal Notice - removal from supply chain
  - Recall Notice - recall from consumers
  - Seizure Notice - confiscation of goods

  ## Case Types

  - Prosecution - criminal conviction with fines, costs, confiscation, imprisonment

  ## Legal Basis

  - General Product Safety Regulations 2005
  - Electrical Equipment (Safety) Regulations 2016
  - Construction Products Regulations 2013
  - Ecodesign for Energy-Related Products Regulations 2010
  - Toys (Safety) Regulations 2011
  """

  @behaviour EhsEnforcement.Scraping.AgencyBehavior

  require Logger

  alias EhsEnforcement.Scraping.ScrapeSession
  alias EhsEnforcement.Scraping.Opss.OpssEnforcementScraper
  alias EhsEnforcement.Scraping.Opss.OpssNoticeProcessor
  alias EhsEnforcement.Scraping.Opss.OpssCaseProcessor

  @impl true
  def validate_params(opts) do
    Logger.debug("OPSS: Validating parameters: #{inspect(opts)}")

    # OPSS-specific parameters
    periods = Keyword.get(opts, :periods)
    data_type = Keyword.get(opts, :data_type, :all)
    actor = Keyword.get(opts, :actor)
    scrape_type = Keyword.get(opts, :scrape_type, :manual)

    # Validate data_type parameter
    valid_data_types = [:all, :notices, :prosecutions]

    if data_type not in valid_data_types do
      {:error, "Invalid data_type: #{data_type}. Must be one of: #{inspect(valid_data_types)}"}
    else
      validated_params = %{
        periods: periods,
        data_type: data_type,
        actor: actor,
        scrape_type: scrape_type
      }

      Logger.debug("OPSS: Parameters validated successfully")
      {:ok, validated_params}
    end
  end

  @impl true
  def start_scraping(validated_params, _config) do
    Logger.info("OPSS: Starting scraping session",
      data_type: validated_params.data_type,
      periods: validated_params.periods
    )

    # Create Ash ScrapeSession record
    session_id = EhsEnforcement.Scraping.AgencyBehavior.generate_session_id()

    # Get available periods
    periods = validated_params.periods || OpssEnforcementScraper.available_periods()

    ash_session_params = %{
      session_id: session_id,
      agency: :opss,
      start_page: 1,
      max_pages: length(periods),
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
        Logger.metadata(session_id: session.session_id, agency: :opss)
        Logger.info("OPSS: Created scraping session #{session.session_id}")

        # Store validated_params in session for execution
        session_with_params = Map.put(session, :validated_params, validated_params)

        # Execute the OPSS scraping workflow
        execute_opss_scraping_session(session_with_params)

      {:error, reason} ->
        Logger.error("OPSS: Failed to create ScrapeSession record: #{inspect(reason)}")
        {:error, "Failed to create OPSS scraping session: #{inspect(reason)}"}
    end
  end

  @impl true
  def process_results(session_results) do
    Logger.info("OPSS: Processing scraping results",
      session_id: session_results.session_id,
      status: session_results.status,
      cases_created: session_results.cases_created
    )

    session_results
  end

  # Private functions for OPSS-specific implementation

  defp data_type_to_database(:all), do: "all"
  defp data_type_to_database(:notices), do: "notices"
  defp data_type_to_database(:prosecutions), do: "prosecutions"

  defp execute_opss_scraping_session(session) do
    Logger.info("OPSS: Starting execution of scraping session: #{session.session_id}")

    validated_params = Map.get(session, :validated_params, %{})

    # Scrape OPSS data
    scrape_opts =
      if validated_params.periods do
        [periods: validated_params.periods]
      else
        []
      end

    case OpssEnforcementScraper.scrape_all(scrape_opts) do
      {:ok, scraped_actions} ->
        Logger.info("OPSS: Scraped #{length(scraped_actions)} enforcement actions")

        # Update session with found count
        session = update_session(session, %{cases_found: length(scraped_actions)})

        # Process based on data_type
        case validated_params.data_type do
          :notices ->
            process_notices_only(session, scraped_actions)

          :prosecutions ->
            process_prosecutions_only(session, scraped_actions)

          :all ->
            process_all_actions(session, scraped_actions)
        end
        |> finalize_session()

      {:ok, scraped_actions, errors: scrape_errors} ->
        Logger.warning("OPSS: Scraped with #{length(scrape_errors)} period errors")

        session =
          update_session(session, %{
            cases_found: length(scraped_actions),
            errors_count: length(scrape_errors)
          })

        case validated_params.data_type do
          :notices ->
            process_notices_only(session, scraped_actions)

          :prosecutions ->
            process_prosecutions_only(session, scraped_actions)

          :all ->
            process_all_actions(session, scraped_actions)
        end
        |> finalize_session()
    end
  end

  defp process_notices_only(session, actions) do
    notices = OpssNoticeProcessor.filter_notices(actions)
    Logger.info("OPSS: Processing #{length(notices)} notices")
    process_notices_serially(session, notices)
  end

  defp process_prosecutions_only(session, actions) do
    prosecutions = OpssCaseProcessor.filter_prosecutions(actions)
    Logger.info("OPSS: Processing #{length(prosecutions)} prosecutions")
    process_prosecutions_serially(session, prosecutions)
  end

  defp process_all_actions(session, actions) do
    notices = OpssNoticeProcessor.filter_notices(actions)
    prosecutions = OpssCaseProcessor.filter_prosecutions(actions)

    Logger.info(
      "OPSS: Processing #{length(notices)} notices and #{length(prosecutions)} prosecutions"
    )

    # Process notices first
    session = process_notices_serially(session, notices)

    # Then process prosecutions
    process_prosecutions_serially(session, prosecutions)
  end

  defp process_notices_serially(session, notices) do
    Logger.info("OPSS: Processing #{length(notices)} notices serially")

    validated_params = Map.get(session, :validated_params, %{})
    actor = Map.get(validated_params, :actor)

    Enum.reduce(notices, session, fn action, current_session ->
      result = OpssNoticeProcessor.process_and_create_notice(action, actor)
      handle_notice_result(result, current_session)
    end)
  end

  defp handle_notice_result({:ok, :duplicate}, session) do
    Logger.debug("OPSS: Notice already exists")

    update_session(session, %{
      cases_processed: session.cases_processed + 1,
      cases_exist_total: session.cases_exist_total + 1
    })
  end

  defp handle_notice_result({:ok, created_notice}, session) do
    Logger.debug("OPSS: Created notice: #{created_notice.regulator_id}")

    update_session(session, %{
      cases_processed: session.cases_processed + 1,
      cases_created: session.cases_created + 1
    })
  end

  defp handle_notice_result({:error, %Ash.Error.Invalid{errors: errors}}, session) do
    if duplicate_error?(errors) do
      Logger.debug("OPSS: Notice already exists (duplicate)")

      update_session(session, %{
        cases_processed: session.cases_processed + 1,
        cases_exist_total: session.cases_exist_total + 1
      })
    else
      Logger.warning("OPSS: Error creating notice: #{inspect(errors)}")

      update_session(session, %{
        cases_processed: session.cases_processed + 1,
        errors_count: session.errors_count + 1
      })
    end
  end

  defp handle_notice_result({:error, reason}, session) do
    Logger.warning("OPSS: Error processing notice: #{inspect(reason)}")

    update_session(session, %{
      cases_processed: session.cases_processed + 1,
      errors_count: session.errors_count + 1
    })
  end

  defp process_prosecutions_serially(session, prosecutions) do
    Logger.info("OPSS: Processing #{length(prosecutions)} prosecutions serially")

    validated_params = Map.get(session, :validated_params, %{})
    actor = Map.get(validated_params, :actor)

    Enum.reduce(prosecutions, session, fn action, current_session ->
      result = OpssCaseProcessor.process_and_create_case(action, actor)
      handle_case_result(result, current_session)
    end)
  end

  defp handle_case_result({:ok, :duplicate}, session) do
    Logger.debug("OPSS: Case already exists")

    update_session(session, %{
      cases_processed: session.cases_processed + 1,
      cases_exist_total: session.cases_exist_total + 1
    })
  end

  defp handle_case_result({:ok, created_case}, session) do
    Logger.debug("OPSS: Created case: #{created_case.regulator_id}")

    update_session(session, %{
      cases_processed: session.cases_processed + 1,
      cases_created: session.cases_created + 1
    })
  end

  defp handle_case_result({:error, %Ash.Error.Invalid{errors: errors}}, session) do
    if duplicate_error?(errors) do
      Logger.debug("OPSS: Case already exists (duplicate)")

      update_session(session, %{
        cases_processed: session.cases_processed + 1,
        cases_exist_total: session.cases_exist_total + 1
      })
    else
      Logger.warning("OPSS: Error creating case: #{inspect(errors)}")

      update_session(session, %{
        cases_processed: session.cases_processed + 1,
        errors_count: session.errors_count + 1
      })
    end
  end

  defp handle_case_result({:error, reason}, session) do
    Logger.warning("OPSS: Error processing prosecution: #{inspect(reason)}")

    update_session(session, %{
      cases_processed: session.cases_processed + 1,
      errors_count: session.errors_count + 1
    })
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
        Logger.error("OPSS: Failed to update session: #{inspect(reason)}")
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

    # Calculate pages processed (number of periods)
    validated_params = Map.get(session, :validated_params, %{})
    periods = validated_params[:periods] || OpssEnforcementScraper.available_periods()

    case Ash.update(session, %{status: final_status, pages_processed: length(periods)}) do
      {:ok, final_session} ->
        Logger.info("OPSS: Session finalized",
          session_id: final_session.session_id,
          status: final_session.status,
          created: final_session.cases_created,
          existing: final_session.cases_exist_total,
          errors: final_session.errors_count
        )

        {:ok, final_session}

      {:error, reason} ->
        Logger.error("OPSS: Failed to finalize session: #{inspect(reason)}")
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
end
