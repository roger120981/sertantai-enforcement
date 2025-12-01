defmodule EhsEnforcement.Scraping.Opss.OpssCaseProcessor do
  @moduledoc """
  OPSS case (prosecution) processing pipeline - transforms scraped enforcement actions for Ash Case resource creation.

  Handles:
  - Data transformation from OPSS format to Case resource format
  - Offender creation/lookup
  - Deterministic regulator_id generation for deduplication
  - Filtering prosecutions from notice types

  ## Data Flow

  ```
  ScrapedAction (Prosecution type only)
    → ProcessedCase
      → Case (with Offender, Agency)
  ```

  ## Prosecution Details

  OPSS prosecutions include:
  - Fines (monetary penalties)
  - Costs (legal costs awarded)
  - Confiscation orders (proceeds of crime)
  - Imprisonment (custodial sentences, often suspended)
  """

  require Logger

  alias EhsEnforcement.Scraping.Opss.OpssEnforcementScraper.ScrapedAction

  @opss_agency_code :opss

  defmodule ProcessedCase do
    @moduledoc "Struct representing a prosecution ready for Ash Case resource creation"

    @derive Jason.Encoder
    defstruct [
      :regulator_id,
      :agency_code,
      :offender_attrs,
      :offence_hearing_date,
      :offence_action_date,
      :offence_fine,
      :offence_costs,
      :offence_result,
      :offence_breaches,
      :offence_action_type,
      :url,
      :source_metadata
    ]
  end

  @doc """
  Check if an action type is a prosecution (not a notice).

  Returns true only for "Prosecution" action type.
  """
  def is_prosecution?(action_type) when is_binary(action_type) do
    action_type == "Prosecution"
  end

  def is_prosecution?(_), do: false

  @doc """
  Filter scraped actions to only include prosecutions (exclude notices).

  Returns a list of ScrapedAction structs that are prosecution types.
  """
  def filter_prosecutions(actions) when is_list(actions) do
    Enum.filter(actions, fn action ->
      is_prosecution?(action.action_type)
    end)
  end

  @doc """
  Process a single scraped prosecution action into format ready for Ash Case resource creation.

  Returns {:ok, %ProcessedCase{}} or {:error, reason}
  """
  def process_case(%ScrapedAction{} = action) do
    Logger.debug("OPSS: Processing prosecution for #{action.business_name}")

    try do
      # Generate deterministic regulator_id for deduplication
      regulator_id = generate_regulator_id(action)

      # Build offence result text (includes products, detail, imprisonment, confiscation)
      offence_result = build_offence_result(action)

      # Build offence breaches text (court + legislation)
      offence_breaches = build_offence_breaches(action)

      processed = %ProcessedCase{
        regulator_id: regulator_id,
        agency_code: @opss_agency_code,
        offender_attrs: build_offender_attrs(action),
        offence_hearing_date: action.action_date,
        offence_action_date: action.action_date,
        offence_fine: action.fine,
        offence_costs: action.costs,
        offence_result: offence_result,
        offence_breaches: offence_breaches,
        offence_action_type: "OPSS Prosecution",
        url: build_source_url(action),
        source_metadata: build_source_metadata(action)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("OPSS: Failed to process prosecution: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped actions in batch (prosecutions only).

  Returns {:ok, [%ProcessedCase{}]} or {:ok, [%ProcessedCase{}], errors: [...]}
  """
  def process_cases(scraped_actions) when is_list(scraped_actions) do
    # Filter to prosecutions only before processing
    prosecutions = filter_prosecutions(scraped_actions)

    Logger.info(
      "OPSS: Processing #{length(prosecutions)} prosecution actions (from #{length(scraped_actions)} total)"
    )

    if Enum.empty?(prosecutions) do
      {:ok, []}
    else
      {processed, errors} =
        Enum.reduce(prosecutions, {[], []}, fn action, {proc_acc, err_acc} ->
          case process_case(action) do
            {:ok, processed_case} ->
              {[processed_case | proc_acc], err_acc}

            {:error, reason} ->
              identifier = "#{action.action_type}:#{action.business_name}@#{action.period}"
              {proc_acc, [{identifier, reason} | err_acc]}
          end
        end)

      processed_list = Enum.reverse(processed)

      if errors == [] do
        Logger.info("OPSS: Successfully processed all #{length(processed_list)} prosecutions")
        {:ok, processed_list}
      else
        Logger.warning(
          "OPSS: Processed #{length(processed_list)} prosecutions with #{length(errors)} errors"
        )

        {:ok, processed_list, errors: Enum.reverse(errors)}
      end
    end
  end

  @doc """
  Create a Case from processed data using Ash patterns.

  Returns {:ok, %Case{}} or {:error, reason}
  """
  def create_case_from_processed(%ProcessedCase{} = processed, actor) do
    Logger.debug("OPSS: Creating case from processed data: #{processed.regulator_id}")

    # Get OPSS agency
    case EhsEnforcement.Enforcement.get_agency_by_code(processed.agency_code) do
      {:ok, agency} when not is_nil(agency) ->
        # Find or create offender
        case EhsEnforcement.Enforcement.Offender.find_or_create_offender(processed.offender_attrs) do
          {:ok, offender} ->
            # Create case using Ash
            case_attrs = %{
              regulator_id: processed.regulator_id,
              offence_hearing_date: processed.offence_hearing_date,
              offence_action_date: processed.offence_action_date,
              offence_fine: processed.offence_fine,
              offence_costs: processed.offence_costs,
              offence_result: processed.offence_result,
              offence_breaches: processed.offence_breaches,
              offence_action_type: processed.offence_action_type,
              url: processed.url,
              agency_id: agency.id,
              offender_id: offender.id,
              last_synced_at: DateTime.utc_now()
            }

            case EhsEnforcement.Enforcement.Case
                 |> Ash.Changeset.for_create(:create, case_attrs)
                 |> Ash.create(actor: actor) do
              {:ok, created_case} ->
                {:ok, created_case}

              {:error, %Ash.Error.Invalid{} = ash_error} ->
                # Check if it's a duplicate
                if duplicate_error?(ash_error) do
                  Logger.debug("OPSS: Case already exists: #{processed.regulator_id}")
                  {:ok, :duplicate}
                else
                  Logger.error("OPSS: Failed to create case: #{inspect(ash_error)}")
                  {:error, ash_error}
                end

              {:error, reason} ->
                Logger.error("OPSS: Failed to create case: #{inspect(reason)}")
                {:error, {:case_creation_error, reason}}
            end

          {:error, reason} ->
            Logger.error("OPSS: Failed to find/create offender: #{inspect(reason)}")
            {:error, {:offender_error, reason}}
        end

      {:ok, nil} ->
        {:error, {:agency_not_found, processed.agency_code}}

      {:error, reason} ->
        {:error, {:agency_error, reason}}
    end
  end

  @doc """
  Process and create a single prosecution using Ash patterns.

  Returns {:ok, %Case{}} or {:error, reason}
  """
  def process_and_create_case(%ScrapedAction{} = action, actor) do
    case process_case(action) do
      {:ok, processed} ->
        create_case_from_processed(processed, actor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Process and create all prosecutions from scraped data.

  Returns {:ok, %{created: count, duplicates: count, errors: count}}
  """
  def process_and_create_all(scraped_actions, actor) when is_list(scraped_actions) do
    prosecutions = filter_prosecutions(scraped_actions)
    Logger.info("OPSS: Processing and creating #{length(prosecutions)} prosecutions")

    results =
      Enum.reduce(prosecutions, %{created: 0, duplicates: 0, errors: []}, fn action, acc ->
        case process_and_create_case(action, actor) do
          {:ok, :duplicate} ->
            %{acc | duplicates: acc.duplicates + 1}

          {:ok, _case} ->
            %{acc | created: acc.created + 1}

          {:error, reason} ->
            identifier = "#{action.action_type}:#{action.business_name}@#{action.period}"
            %{acc | errors: [{identifier, reason} | acc.errors]}
        end
      end)

    Logger.info(
      "OPSS: Created #{results.created}, duplicates #{results.duplicates}, errors #{length(results.errors)}"
    )

    {:ok, results}
  end

  # Private Functions

  defp generate_regulator_id(action) do
    # Format: opss_prosecution_{date}_{business_slug}
    # Example: opss_prosecution_20240615_dangerous_toys_ltd

    business_slug =
      (action.business_name || "unknown")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.slice(0, 40)
      |> String.trim("_")

    date_part =
      case action.action_date do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> extract_period_date(action.period)
      end

    "opss_prosecution_#{date_part}_#{business_slug}"
  end

  defp extract_period_date(nil), do: "00000000"

  defp extract_period_date(period) do
    # Extract year and approximate date from period string
    # e.g., "opss-enforcement-actions-1-april-2024-to-30-september-2024"
    case Regex.run(~r/(\d{4})/, period) do
      [_, year] -> "#{year}0000"
      nil -> "00000000"
    end
  end

  defp build_offender_attrs(action) do
    %{
      name: action.business_name || "[Unknown Business]",
      country: "United Kingdom"
    }
  end

  defp build_offence_result(action) do
    parts = []

    # Add category
    parts =
      if action.category && String.length(action.category) > 0 do
        ["Category: #{action.category}" | parts]
      else
        parts
      end

    # Add products
    parts =
      if action.products && String.length(action.products) > 0 do
        ["Products: #{action.products}" | parts]
      else
        parts
      end

    # Add detail
    parts =
      if action.detail && String.length(action.detail) > 0 do
        ["Detail: #{action.detail}" | parts]
      else
        parts
      end

    # Add imprisonment if applicable
    parts =
      if action.imprisonment && String.length(action.imprisonment) > 0 do
        ["Sentence: #{action.imprisonment}" | parts]
      else
        parts
      end

    # Add confiscation if applicable
    parts =
      if action.confiscation && action.confiscation > 0 do
        ["Confiscation: #{action.confiscation}" | parts]
      else
        parts
      end

    parts
    |> Enum.reverse()
    |> Enum.join("\n\n")
    |> String.trim()
  end

  defp build_offence_breaches(action) do
    parts = []

    # Add court
    parts =
      if action.court && String.length(action.court) > 0 do
        ["Court: #{action.court}" | parts]
      else
        parts
      end

    # Add breached regulations
    parts =
      if action.breached_regulations && String.length(action.breached_regulations) > 0 do
        ["Breaches: #{action.breached_regulations}" | parts]
      else
        parts
      end

    parts
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp build_source_url(action) do
    if action.period && String.length(action.period) > 0 do
      "https://www.gov.uk/government/publications/opss-enforcement-actions/#{action.period}"
    else
      "https://www.gov.uk/government/publications/opss-enforcement-actions"
    end
  end

  defp build_source_metadata(action) do
    %{
      scraped_at: action.scrape_timestamp,
      scraper_version: "1.0",
      source: "gov.uk",
      period: action.period,
      category: action.category,
      products: action.products,
      breached_regulations: action.breached_regulations,
      court: action.court,
      fine: action.fine,
      costs: action.costs,
      confiscation: action.confiscation,
      imprisonment: action.imprisonment
    }
  end

  defp duplicate_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn error ->
      case error do
        %Ash.Error.Changes.InvalidChanges{message: msg} ->
          String.contains?(msg || "", "already exists")

        _ ->
          false
      end
    end)
  end

  defp duplicate_error?(_), do: false
end
