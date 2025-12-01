defmodule EhsEnforcement.Scraping.Opss.OpssNoticeProcessor do
  @moduledoc """
  OPSS notice processing pipeline - transforms scraped enforcement actions for Ash Notice resource creation.

  Handles:
  - Data transformation from OPSS format to Notice resource format
  - Offender creation/lookup
  - Deterministic regulator_id generation for deduplication
  - Filtering notices from prosecutions

  ## Data Flow

  ```
  ScrapedAction (Notice types only)
    → ProcessedNotice
      → Notice (with Offender, Agency)
  ```

  ## Notice Types

  - **Compliance Notice**: Requires corrective action
  - **Stop Notice**: Prohibits placing on market
  - **Prohibition Notice**: Prohibits supply
  - **Withdrawal Notice**: Removal from supply chain
  - **Recall Notice**: Recall from consumers
  - **Seizure Notice**: Confiscation of goods
  """

  require Logger

  alias EhsEnforcement.Scraping.Opss.OpssEnforcementScraper.ScrapedAction

  @opss_agency_code :opss

  @notice_types [
    "Compliance Notice",
    "Stop Notice",
    "Prohibition Notice",
    "Withdrawal Notice",
    "Recall Notice",
    "Seizure Notice"
  ]

  defmodule ProcessedNotice do
    @moduledoc "Struct representing a notice ready for Ash Notice resource creation"

    @derive Jason.Encoder
    defstruct [
      :regulator_id,
      :agency_code,
      :offender_attrs,
      :notice_date,
      :notice_body,
      :offence_action_type,
      :offence_action_date,
      :offence_breaches,
      :url,
      :source_metadata
    ]
  end

  @doc """
  Check if an action type is a notice (not a prosecution).

  Returns true for Stop, Prohibition, Recall, Withdrawal, Compliance, Seizure notices.
  """
  def is_notice?(action_type) when is_binary(action_type) do
    action_type in @notice_types
  end

  def is_notice?(_), do: false

  @doc """
  Filter scraped actions to only include notices (exclude prosecutions).

  Returns a list of ScrapedAction structs that are notice types.
  """
  def filter_notices(actions) when is_list(actions) do
    Enum.filter(actions, fn action ->
      is_notice?(action.action_type)
    end)
  end

  @doc """
  Process a single scraped action into format ready for Ash Notice resource creation.

  Returns {:ok, %ProcessedNotice{}} or {:error, reason}
  """
  def process_notice(%ScrapedAction{} = action) do
    Logger.debug("OPSS: Processing #{action.action_type} for #{action.business_name}")

    try do
      # Generate deterministic regulator_id for deduplication
      regulator_id = generate_regulator_id(action)

      # Map action type to OPSS-prefixed action type string
      action_type = "OPSS #{action.action_type}"

      # Build notice body from action data
      notice_body = build_notice_body(action)

      processed = %ProcessedNotice{
        regulator_id: regulator_id,
        agency_code: @opss_agency_code,
        offender_attrs: build_offender_attrs(action),
        notice_date: action.action_date,
        notice_body: notice_body,
        offence_action_type: action_type,
        offence_action_date: action.action_date,
        offence_breaches: action.breached_regulations,
        url: build_source_url(action),
        source_metadata: build_source_metadata(action)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("OPSS: Failed to process action: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped actions in batch (notices only).

  Returns {:ok, [%ProcessedNotice{}]} or {:ok, [%ProcessedNotice{}], errors: [...]}
  """
  def process_notices(scraped_actions) when is_list(scraped_actions) do
    # Filter to notices only before processing
    notices = filter_notices(scraped_actions)

    Logger.info(
      "OPSS: Processing #{length(notices)} notice actions (from #{length(scraped_actions)} total)"
    )

    if Enum.empty?(notices) do
      {:ok, []}
    else
      {processed, errors} =
        Enum.reduce(notices, {[], []}, fn action, {proc_acc, err_acc} ->
          case process_notice(action) do
            {:ok, processed_notice} ->
              {[processed_notice | proc_acc], err_acc}

            {:error, reason} ->
              identifier = "#{action.action_type}:#{action.business_name}@#{action.period}"
              {proc_acc, [{identifier, reason} | err_acc]}
          end
        end)

      processed_list = Enum.reverse(processed)

      if errors == [] do
        Logger.info("OPSS: Successfully processed all #{length(processed_list)} notices")
        {:ok, processed_list}
      else
        Logger.warning(
          "OPSS: Processed #{length(processed_list)} notices with #{length(errors)} errors"
        )

        {:ok, processed_list, errors: Enum.reverse(errors)}
      end
    end
  end

  @doc """
  Create a Notice from processed data using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def create_notice_from_processed(%ProcessedNotice{} = processed, actor) do
    Logger.debug("OPSS: Creating notice from processed data: #{processed.regulator_id}")

    # Get OPSS agency
    case EhsEnforcement.Enforcement.get_agency_by_code(processed.agency_code) do
      {:ok, agency} when not is_nil(agency) ->
        # Find or create offender
        case EhsEnforcement.Enforcement.Offender.find_or_create_offender(processed.offender_attrs) do
          {:ok, offender} ->
            # Create notice using Ash
            notice_attrs = %{
              regulator_id: processed.regulator_id,
              notice_date: processed.notice_date,
              notice_body: processed.notice_body,
              offence_action_type: processed.offence_action_type,
              offence_action_date: processed.offence_action_date,
              offence_breaches: processed.offence_breaches,
              url: processed.url,
              agency_id: agency.id,
              offender_id: offender.id,
              last_synced_at: DateTime.utc_now()
            }

            case EhsEnforcement.Enforcement.Notice
                 |> Ash.Changeset.for_create(:create, notice_attrs)
                 |> Ash.create(actor: actor) do
              {:ok, created_notice} ->
                {:ok, created_notice}

              {:error, %Ash.Error.Invalid{} = ash_error} ->
                # Check if it's a duplicate
                if duplicate_error?(ash_error) do
                  Logger.debug("OPSS: Notice already exists: #{processed.regulator_id}")
                  {:ok, :duplicate}
                else
                  Logger.error("OPSS: Failed to create notice: #{inspect(ash_error)}")
                  {:error, ash_error}
                end

              {:error, reason} ->
                Logger.error("OPSS: Failed to create notice: #{inspect(reason)}")
                {:error, {:notice_creation_error, reason}}
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
  Process and create a single notice using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def process_and_create_notice(%ScrapedAction{} = action, actor) do
    case process_notice(action) do
      {:ok, processed} ->
        create_notice_from_processed(processed, actor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Process and create all notices from scraped data.

  Returns {:ok, %{created: count, duplicates: count, errors: count}}
  """
  def process_and_create_all(scraped_actions, actor) when is_list(scraped_actions) do
    notices = filter_notices(scraped_actions)
    Logger.info("OPSS: Processing and creating #{length(notices)} notices")

    results =
      Enum.reduce(notices, %{created: 0, duplicates: 0, errors: []}, fn action, acc ->
        case process_and_create_notice(action, actor) do
          {:ok, :duplicate} ->
            %{acc | duplicates: acc.duplicates + 1}

          {:ok, _notice} ->
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
    # Format: opss_{type_slug}_{date_or_period}_{business_slug}
    # Example: opss_stop_20241015_test_business_ltd

    type_slug =
      action.action_type
      |> String.downcase()
      |> String.replace(" ", "_")
      |> String.replace(~r/[^a-z0-9_]/, "")

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

    "opss_#{type_slug}_#{date_part}_#{business_slug}"
  end

  defp extract_period_date(nil), do: "00000000"

  defp extract_period_date(period) do
    # Extract year and approximate date from period string
    # e.g., "opss-enforcement-actions-1-october-2024-to-31-march-2025"
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

  defp build_notice_body(action) do
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

    # Add breached regulations
    parts =
      if action.breached_regulations && String.length(action.breached_regulations) > 0 do
        ["Breached Regulations: #{action.breached_regulations}" | parts]
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

    parts
    |> Enum.reverse()
    |> Enum.join("\n\n")
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
      breached_regulations: action.breached_regulations
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
