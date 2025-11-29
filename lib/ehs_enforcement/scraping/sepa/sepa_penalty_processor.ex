defmodule EhsEnforcement.Scraping.Sepa.SepaPenaltyProcessor do
  @moduledoc """
  SEPA penalty processing pipeline - transforms scraped data for Ash resource creation.

  Handles:
  - Data transformation from SEPA format to Notice resource format
  - Offender creation/lookup with Scotland country assignment
  - Deterministic regulator_id generation for deduplication
  - Mapping of SEPA penalty types to offence_action_type
  """

  require Logger

  alias EhsEnforcement.Scraping.Sepa.SepaPenaltyScraper.ScrapedPenalty
  alias EhsEnforcement.Scraping.Shared.DateParser

  @sepa_agency_code :sepa

  defmodule ProcessedPenalty do
    @moduledoc "Struct representing a penalty ready for Ash Notice resource creation"

    @derive Jason.Encoder
    defstruct [
      :regulator_id,
      :agency_code,
      :offender_attrs,
      :notice_date,
      :notice_body,
      :offence_action_type,
      :offence_breaches,
      :penalty_amount,
      :url,
      :source_metadata
    ]
  end

  @doc """
  Process a single scraped penalty into format ready for Ash Notice resource creation.

  Returns {:ok, %ProcessedPenalty{}} or {:error, reason}
  """
  def process_penalty(%ScrapedPenalty{} = penalty) do
    Logger.debug("SEPA: Processing penalty for #{penalty.name_and_address}")

    try do
      # Parse offender name and address
      {name, address, postcode} = parse_name_and_address(penalty.name_and_address)

      # Generate deterministic regulator_id for deduplication
      regulator_id = generate_regulator_id(penalty, name)

      processed = %ProcessedPenalty{
        regulator_id: regulator_id,
        agency_code: @sepa_agency_code,
        offender_attrs: build_offender_attrs(name, address, postcode),
        notice_date: parse_date(penalty.date),
        notice_body: penalty.offence_details,
        offence_action_type: map_penalty_type(penalty),
        offence_breaches: penalty.legislation_breached,
        penalty_amount: penalty.penalty_amount,
        url: penalty.documentation_url,
        source_metadata: build_source_metadata(penalty)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("SEPA: Failed to process penalty: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped penalties in batch.

  Returns {:ok, [%ProcessedPenalty{}]} or {:ok, [%ProcessedPenalty{}], errors: [...]}
  """
  def process_penalties(scraped_penalties) when is_list(scraped_penalties) do
    Logger.info("SEPA: Processing #{length(scraped_penalties)} scraped penalties")

    {processed, errors} =
      Enum.reduce(scraped_penalties, {[], []}, fn penalty, {proc_acc, err_acc} ->
        case process_penalty(penalty) do
          {:ok, processed_penalty} ->
            {[processed_penalty | proc_acc], err_acc}

          {:error, reason} ->
            {proc_acc, [{penalty.name_and_address, reason} | err_acc]}
        end
      end)

    processed_list = Enum.reverse(processed)

    if errors == [] do
      Logger.info("SEPA: Successfully processed all #{length(processed_list)} penalties")
      {:ok, processed_list}
    else
      Logger.warning(
        "SEPA: Processed #{length(processed_list)} penalties with #{length(errors)} errors"
      )

      {:ok, processed_list, errors: Enum.reverse(errors)}
    end
  end

  @doc """
  Process and create a single penalty as a Notice using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def process_and_create_penalty(%ScrapedPenalty{} = penalty, actor) do
    case process_penalty(penalty) do
      {:ok, processed} ->
        create_notice_from_processed(processed, actor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a Notice from processed penalty data using Ash patterns.

  Returns {:ok, %Notice{}} or {:error, reason}
  """
  def create_notice_from_processed(%ProcessedPenalty{} = processed, actor) do
    Logger.debug("SEPA: Creating notice from processed penalty: #{processed.regulator_id}")

    # Get SEPA agency
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
              offence_breaches: processed.offence_breaches,
              penalty_amount: processed.penalty_amount,
              url: processed.url,
              agency_id: agency.id,
              offender_id: offender.id,
              last_synced_at: DateTime.utc_now()
            }

            EhsEnforcement.Enforcement.Notice
            |> Ash.Changeset.for_create(:create, notice_attrs)
            |> Ash.create(actor: actor)

          {:error, reason} ->
            Logger.error("SEPA: Failed to find/create offender: #{inspect(reason)}")
            {:error, {:offender_error, reason}}
        end

      {:ok, nil} ->
        {:error, "Agency not found: #{processed.agency_code}"}

      {:error, reason} ->
        {:error, {:agency_error, reason}}
    end
  end

  # Private Functions

  defp parse_name_and_address(nil), do: {nil, nil, nil}
  defp parse_name_and_address(""), do: {nil, nil, nil}
  defp parse_name_and_address("Information not published"), do: {"[Name withheld]", nil, nil}

  defp parse_name_and_address(text) do
    # SEPA format: "Name, Location, Postcode"
    # Examples:
    #   "Hugh Hodge, Mauchline, KA5"
    #   "Essbee Coaches Ltd, Hamilton, ML30BP"
    #   "The Pine Trees Hotel Ltd c/o David Lapsley, Pitlochry, PH16"
    #   "Patersons of Greenoakhill Limited, Gartsherrie Road, Coatbridge, ML5 2EU"

    parts = String.split(text, ",") |> Enum.map(&String.trim/1)

    case parts do
      [name] ->
        {name, nil, nil}

      [name, location] ->
        postcode = extract_postcode(location)
        {name, location, postcode}

      [name | rest] ->
        # Last part is typically the postcode
        last_part = List.last(rest)
        postcode = extract_postcode(last_part)

        # Build address from all parts except name
        address = Enum.join(rest, ", ")

        {name, address, postcode}
    end
  end

  defp extract_postcode(text) when is_binary(text) do
    # UK postcode pattern: e.g., "KA5", "ML30BP", "ML5 2EU", "PH16"
    # Match both full postcodes and outward codes only
    case Regex.run(~r/([A-Z]{1,2}\d{1,2}[A-Z]?\s*\d?[A-Z]{0,2})$/i, text) do
      [_, postcode] -> String.upcase(postcode) |> String.trim()
      _ -> nil
    end
  end

  defp extract_postcode(_), do: nil

  defp build_offender_attrs(name, address, postcode) do
    %{
      name: name || "[Unknown]",
      address: address,
      postcode: postcode,
      country: "Scotland"
    }
  end

  defp generate_regulator_id(penalty, name) do
    # Generate deterministic ID: sepa_{YYYYMMDD}_{name_hash_8chars}
    # This allows deduplication on re-scrape

    date_part =
      case parse_date(penalty.date) do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    name_hash =
      (name || "unknown")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 8)

    "sepa_#{date_part}_#{name_hash}"
  end

  defp map_penalty_type(%ScrapedPenalty{
         penalty_type: type,
         penalty_amount: amount,
         section_type: section
       }) do
    case section do
      :penalties ->
        case {normalize_penalty_type(type), amount} do
          {"fixed monetary penalty", %Decimal{} = amt} ->
            amt_int = amt |> Decimal.round(0) |> Decimal.to_integer()
            "SEPA FMP £#{amt_int}"

          {"fixed monetary penalty", _} ->
            "SEPA FMP"

          {"variable monetary penalty", _} ->
            "SEPA VMP"

          _ ->
            "SEPA Penalty"
        end

      :undertakings ->
        "SEPA Undertaking"

      :costs_recovery ->
        "SEPA Costs Recovery"

      _ ->
        "SEPA Enforcement"
    end
  end

  defp normalize_penalty_type(nil), do: nil

  defp normalize_penalty_type(type) do
    type
    |> String.downcase()
    |> String.trim()
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) do
    # SEPA date format: "16 July 2025", "9 January 2025", etc.
    DateParser.parse_date(date_string)
  end

  defp build_source_metadata(penalty) do
    %{
      scraped_at: penalty.scrape_timestamp,
      scraper_version: "1.0",
      source: "beta.sepa.scot",
      section_type: penalty.section_type,
      year: penalty.year
    }
  end
end
