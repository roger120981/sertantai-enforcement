defmodule EhsEnforcement.Scraping.Nrw.NrwCaseProcessor do
  @moduledoc """
  NRW case processing pipeline - transforms parsed article data for Ash resource creation.

  Handles:
  - Data transformation from NRW article format to Case resource format
  - Offender creation/lookup with Wales country assignment
  - Deterministic regulator_id generation for deduplication
  - Mapping of NRW enforcement types to offence_action_type
  """

  require Logger

  # Support both the regex-based and AI-based parsers (same struct name)
  alias EhsEnforcement.Scraping.Nrw.NrwAiArticleParser.ParsedCase, as: AiParsedCase
  alias EhsEnforcement.Scraping.Nrw.NrwArticleParser.ParsedCase, as: RegexParsedCase

  @nrw_agency_code :nrw

  defmodule ProcessedCase do
    @moduledoc "Struct representing a case ready for Ash Case resource creation"

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
  Process a single parsed case into format ready for Ash Case resource creation.

  Accepts ParsedCase structs from either the AI parser or regex parser.

  Returns {:ok, %ProcessedCase{}} or {:error, reason}
  """
  def process_case(%AiParsedCase{} = parsed_case), do: do_process_case(parsed_case)
  def process_case(%RegexParsedCase{} = parsed_case), do: do_process_case(parsed_case)

  defp do_process_case(parsed_case) do
    Logger.debug("NRW: Processing case for #{parsed_case.offender_name}")

    try do
      # Generate deterministic regulator_id for deduplication
      regulator_id = generate_regulator_id(parsed_case)

      # Calculate combined costs (costs + surcharge)
      combined_costs = calculate_combined_costs(parsed_case)

      # Determine fine (use POCA if no regular fine)
      fine_amount = parsed_case.fine_amount || parsed_case.poca_amount

      processed = %ProcessedCase{
        regulator_id: regulator_id,
        agency_code: @nrw_agency_code,
        offender_attrs: build_offender_attrs(parsed_case),
        offence_hearing_date: parsed_case.hearing_date,
        offence_action_date: parsed_case.article_date,
        offence_fine: fine_amount,
        offence_costs: combined_costs,
        offence_result: parsed_case.offence_result,
        offence_breaches: parsed_case.legislation,
        offence_action_type: determine_action_type(parsed_case),
        url: parsed_case.article_url,
        source_metadata: build_source_metadata(parsed_case)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("NRW: Failed to process case: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple parsed cases in batch.

  Returns {:ok, [%ProcessedCase{}]} or {:ok, [%ProcessedCase{}], errors: [...]}
  """
  def process_cases(parsed_cases) when is_list(parsed_cases) do
    Logger.info("NRW: Processing #{length(parsed_cases)} parsed cases")

    {processed, errors} =
      Enum.reduce(parsed_cases, {[], []}, fn parsed_case, {proc_acc, err_acc} ->
        case process_case(parsed_case) do
          {:ok, processed_case} ->
            {[processed_case | proc_acc], err_acc}

          {:error, reason} ->
            {proc_acc, [{parsed_case.offender_name, reason} | err_acc]}
        end
      end)

    processed_list = Enum.reverse(processed)

    if errors == [] do
      Logger.info("NRW: Successfully processed all #{length(processed_list)} cases")
      {:ok, processed_list}
    else
      Logger.warning(
        "NRW: Processed #{length(processed_list)} cases with #{length(errors)} errors"
      )

      {:ok, processed_list, errors: Enum.reverse(errors)}
    end
  end

  @doc """
  Process and create a single case using Ash patterns.

  Returns {:ok, %Case{}} or {:error, reason}
  """
  def process_and_create_case(%AiParsedCase{} = parsed_case, actor) do
    case process_case(parsed_case) do
      {:ok, processed} ->
        create_case_from_processed(processed, actor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a Case from processed case data using Ash patterns.

  Returns {:ok, %Case{}} or {:error, reason}
  """
  def create_case_from_processed(%ProcessedCase{} = processed, actor) do
    Logger.debug("NRW: Creating case from processed data: #{processed.regulator_id}")

    # Get NRW agency
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

            EhsEnforcement.Enforcement.Case
            |> Ash.Changeset.for_create(:create, case_attrs)
            |> Ash.create(actor: actor)

          {:error, reason} ->
            Logger.error("NRW: Failed to find/create offender: #{inspect(reason)}")
            {:error, {:offender_error, reason}}
        end

      {:ok, nil} ->
        {:error, "Agency not found: #{processed.agency_code}"}

      {:error, reason} ->
        {:error, {:agency_error, reason}}
    end
  end

  # Private Functions

  defp generate_regulator_id(parsed_case) do
    # Generate deterministic ID: nrw_{YYYYMMDD}_{name_hash_8chars}
    # This allows deduplication on re-scrape

    date_part =
      case parsed_case.hearing_date || parsed_case.article_date do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    name_hash =
      (parsed_case.offender_name || "unknown")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 8)

    "nrw_#{date_part}_#{name_hash}"
  end

  defp build_offender_attrs(parsed_case) do
    %{
      name: parsed_case.offender_name || "[Unknown]",
      address: parsed_case.offender_location,
      country: "Wales"
    }
  end

  defp calculate_combined_costs(parsed_case) do
    costs = parsed_case.costs_amount
    surcharge = parsed_case.surcharge_amount

    case {costs, surcharge} do
      {nil, nil} -> nil
      {c, nil} -> c
      {nil, s} -> s
      {c, s} -> Decimal.add(c, s)
    end
  end

  defp determine_action_type(parsed_case) do
    cond do
      parsed_case.poca_amount && is_nil(parsed_case.fine_amount) ->
        "NRW POCA Confiscation"

      parsed_case.fine_amount ->
        fine_int = parsed_case.fine_amount |> Decimal.round(0) |> Decimal.to_integer()

        cond do
          fine_int >= 100_000 -> "NRW Prosecution (Major)"
          fine_int >= 10_000 -> "NRW Prosecution (Significant)"
          true -> "NRW Prosecution"
        end

      parsed_case.offence_result &&
          String.contains?(parsed_case.offence_result, "community order") ->
        "NRW Prosecution (Community Order)"

      true ->
        "NRW Prosecution"
    end
  end

  defp build_source_metadata(parsed_case) do
    %{
      article_url: parsed_case.article_url,
      article_title: parsed_case.article_title,
      article_date: parsed_case.article_date,
      scraper_version: "1.0",
      source: "naturalresources.wales"
    }
  end
end
