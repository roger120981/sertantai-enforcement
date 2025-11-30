defmodule EhsEnforcement.Scraping.Mca.McaProsecutionProcessor do
  @moduledoc """
  MCA prosecution processing pipeline - transforms scraped data for Ash resource creation.

  Handles:
  - Data transformation from GOV.UK format to Case resource format
  - Offender creation/lookup
  - Legislation lookup/creation via LegislationMatcher
  - Offence record creation linking Case → Legislation
  - Deterministic regulator_id generation for deduplication

  ## Data Flow

  ```
  ScrapedProsecution
    → ProcessedProsecution
      → Case (with Offender)
        → Offence (per legislation citation)
          → Legislation (find or create)
  ```

  ## Legislation Mapping

  Common MCA legislation:
  - Merchant Shipping Act 1995 (ukpga/1995/21)
  - Merchant Shipping (ISM Code) Regulations 2014 (uksi/2014/1512)
  - Fishing Vessels (Codes of Practice) Regulations 2017 (uksi/2017/943)
  """

  require Logger

  alias EhsEnforcement.Scraping.Mca.McaProsecutionScraper.ScrapedProsecution
  alias EhsEnforcement.Enforcement.LegislationMatcher
  alias EhsEnforcement.Utility

  @mca_agency_code :mca

  defmodule ProcessedProsecution do
    @moduledoc "Struct representing a prosecution ready for Ash Case resource creation"

    @derive Jason.Encoder
    defstruct [
      :regulator_id,
      :agency_code,
      :offender_attrs,
      :offence_hearing_date,
      :offence_fine,
      :offence_costs,
      :offence_result,
      :offence_breaches,
      :offence_action_type,
      :url,
      :offences,
      :source_metadata
    ]
  end

  @doc """
  Process a single scraped prosecution into format ready for Ash Case resource creation.

  Returns {:ok, %ProcessedProsecution{}} or {:error, reason}
  """
  def process_prosecution(%ScrapedProsecution{} = prosecution) do
    Logger.debug("MCA: Processing prosecution for #{prosecution.defendant}")

    try do
      # Generate deterministic regulator_id for deduplication
      regulator_id = generate_regulator_id(prosecution)

      # Build offence result text (includes sentences, details)
      offence_result = build_offence_result(prosecution)

      # Build offence breaches text (court + legislation summary)
      offence_breaches = build_offence_breaches(prosecution)

      processed = %ProcessedProsecution{
        regulator_id: regulator_id,
        agency_code: @mca_agency_code,
        offender_attrs: build_offender_attrs(prosecution),
        offence_hearing_date: prosecution.hearing_date,
        offence_fine: prosecution.fine,
        offence_costs: prosecution.costs,
        offence_result: offence_result,
        offence_breaches: offence_breaches,
        offence_action_type: "MCA Prosecution",
        url: build_source_url(prosecution.year),
        offences: prosecution.offences,
        source_metadata: build_source_metadata(prosecution)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("MCA: Failed to process prosecution: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped prosecutions in batch.

  Returns {:ok, [%ProcessedProsecution{}]} or {:ok, [%ProcessedProsecution{}], errors: [...]}
  """
  def process_prosecutions(scraped_prosecutions) when is_list(scraped_prosecutions) do
    Logger.info("MCA: Processing #{length(scraped_prosecutions)} scraped prosecutions")

    {processed, errors} =
      Enum.reduce(scraped_prosecutions, {[], []}, fn prosecution, {proc_acc, err_acc} ->
        case process_prosecution(prosecution) do
          {:ok, processed_prosecution} ->
            {[processed_prosecution | proc_acc], err_acc}

          {:error, reason} ->
            identifier = "#{prosecution.defendant}@#{prosecution.year}"
            {proc_acc, [{identifier, reason} | err_acc]}
        end
      end)

    processed_list = Enum.reverse(processed)

    if errors == [] do
      Logger.info("MCA: Successfully processed all #{length(processed_list)} prosecutions")
      {:ok, processed_list}
    else
      Logger.warning(
        "MCA: Processed #{length(processed_list)} prosecutions with #{length(errors)} errors"
      )

      {:ok, processed_list, errors: Enum.reverse(errors)}
    end
  end

  @doc """
  Process and create a single prosecution using Ash patterns.

  Creates:
  1. Case record (with Offender)
  2. Offence records for each legislation citation
  3. Legislation records (find or create)

  Returns {:ok, %Case{}} or {:error, reason}
  """
  def process_and_create_prosecution(%ScrapedProsecution{} = prosecution, actor) do
    case process_prosecution(prosecution) do
      {:ok, processed} ->
        create_case_from_processed(processed, actor)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a Case from processed data using Ash patterns.

  Also creates linked Offence records for each legislation citation.

  Returns {:ok, %Case{}} or {:error, reason}
  """
  def create_case_from_processed(%ProcessedProsecution{} = processed, actor) do
    Logger.debug("MCA: Creating case from processed data: #{processed.regulator_id}")

    # Get MCA agency
    case EhsEnforcement.Enforcement.get_agency_by_code(processed.agency_code) do
      {:ok, agency} when not is_nil(agency) ->
        # Find or create offender
        case EhsEnforcement.Enforcement.Offender.find_or_create_offender(processed.offender_attrs) do
          {:ok, offender} ->
            # Create case using Ash
            case_attrs = %{
              regulator_id: processed.regulator_id,
              offence_hearing_date: processed.offence_hearing_date,
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
                # Create offence records for each legislation citation
                create_offence_records(created_case, processed.offences, actor)
                {:ok, created_case}

              {:error, %Ash.Error.Invalid{} = ash_error} ->
                Logger.error("MCA: Failed to create case: #{inspect(ash_error)}")
                {:error, ash_error}

              {:error, reason} ->
                Logger.error("MCA: Failed to create case: #{inspect(reason)}")
                {:error, {:case_creation_error, reason}}
            end

          {:error, reason} ->
            Logger.error("MCA: Failed to find/create offender: #{inspect(reason)}")
            {:error, {:offender_error, reason}}
        end

      {:ok, nil} ->
        {:error, "Agency not found: #{processed.agency_code}"}

      {:error, reason} ->
        {:error, {:agency_error, reason}}
    end
  end

  # Private Functions

  defp generate_regulator_id(prosecution) do
    # Format: mca_{year}_{defendant_slug}_{date}
    # Deterministic for deduplication

    year = prosecution.year || "0000"

    defendant_slug =
      (prosecution.defendant || "unknown")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.slice(0, 30)
      |> String.trim("_")

    date_part =
      case prosecution.hearing_date do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    "mca_#{year}_#{defendant_slug}_#{date_part}"
  end

  defp build_offender_attrs(prosecution) do
    # MCA prosecutions don't typically have full addresses
    # Use location if available
    %{
      name: prosecution.defendant || "[Unknown Defendant]",
      address: prosecution.defendant_location,
      country: "United Kingdom"
    }
  end

  defp build_offence_result(prosecution) do
    # Build comprehensive result text including all sentencing details
    parts = []

    # Add case title/summary
    parts =
      if prosecution.case_title do
        [prosecution.case_title | parts]
      else
        parts
      end

    # Add custodial sentence if present
    parts =
      if prosecution.custodial_sentence do
        ["Sentence: #{prosecution.custodial_sentence}" | parts]
      else
        parts
      end

    # Add community service if present
    parts =
      if prosecution.community_service_hours do
        ["Community service: #{prosecution.community_service_hours} hours" | parts]
      else
        parts
      end

    # Add victim surcharge if present
    parts =
      if prosecution.victim_surcharge do
        ["Victim surcharge: #{format_money(prosecution.victim_surcharge)}" | parts]
      else
        parts
      end

    # Add details (truncated if very long)
    parts =
      if prosecution.details do
        details =
          if String.length(prosecution.details) > 2000 do
            String.slice(prosecution.details, 0, 2000) <> "..."
          else
            prosecution.details
          end

        [details | parts]
      else
        parts
      end

    parts
    |> Enum.reverse()
    |> Enum.join("\n\n")
    |> String.trim()
  end

  defp build_offence_breaches(prosecution) do
    # Build breaches text: Court + legislation citations
    parts = []

    # Add court
    parts =
      if prosecution.court do
        ["Court: #{prosecution.court}" | parts]
      else
        parts
      end

    # Add legislation citations
    legislation_text =
      prosecution.offences
      |> Enum.map(fn offence ->
        "#{offence.section} #{offence.legislation}"
      end)
      |> Enum.join("; ")

    parts =
      if String.length(legislation_text) > 0 do
        ["Legislation: #{legislation_text}" | parts]
      else
        parts
      end

    parts
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp build_source_url(year) do
    base = "https://www.gov.uk/government/publications"

    case year do
      2025 -> "#{base}/regulatory-compliance-investigations-team-prosecutions-2025"
      year when year in 2020..2024 -> "#{base}/mca-enforcement-unit-prosecutions-#{year}"
      year -> "#{base}/mca-enforcement-unit-prosecutions-#{year}"
    end
  end

  defp build_source_metadata(prosecution) do
    %{
      scraped_at: prosecution.scrape_timestamp,
      scraper_version: "1.0",
      source: "gov.uk",
      year: prosecution.year,
      case_title: prosecution.case_title,
      defendant_age: prosecution.defendant_age,
      defendant_location: prosecution.defendant_location,
      court: prosecution.court,
      total_penalty: prosecution.total_penalty,
      custodial_sentence: prosecution.custodial_sentence,
      community_service_hours: prosecution.community_service_hours,
      victim_surcharge: prosecution.victim_surcharge
    }
  end

  defp format_money(nil), do: nil

  defp format_money(amount) when is_struct(amount, Decimal) do
    "£#{Decimal.to_string(amount)}"
  end

  defp format_money(amount), do: "£#{amount}"

  # Offence and Legislation creation

  defp create_offence_records(case_record, offences, actor) when is_list(offences) do
    Logger.debug("MCA: Creating #{length(offences)} offence records for case #{case_record.id}")

    offences
    |> Enum.with_index(1)
    |> Enum.each(fn {offence, sequence} ->
      create_single_offence(case_record, offence, sequence, actor)
    end)

    :ok
  end

  defp create_offence_records(_case_record, _, _actor), do: :ok

  defp create_single_offence(case_record, offence_data, sequence, actor) do
    # Parse legislation info
    legislation_title = offence_data.legislation
    legislation_part = offence_data.section

    # Extract year from legislation title
    legislation_year = extract_legislation_year(legislation_title)

    # Determine legislation type
    legislation_type = Utility.determine_legislation_type(legislation_title)

    # Find or create legislation record
    case find_or_create_legislation_record(
           legislation_title,
           legislation_year,
           legislation_type,
           actor
         ) do
      {:ok, legislation_id} ->
        # Create offence record
        offence_attrs = %{
          case_id: case_record.id,
          legislation_id: legislation_id,
          legislation_part: legislation_part,
          offence_description: "#{legislation_part} #{legislation_title}",
          sequence_number: sequence
        }

        case Ash.create(EhsEnforcement.Enforcement.Offence, offence_attrs, actor: actor) do
          {:ok, offence} ->
            Logger.debug("MCA: Created offence #{offence.id} for case #{case_record.id}")

          {:error, reason} ->
            Logger.warning("MCA: Failed to create offence: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("MCA: Failed to find/create legislation: #{inspect(reason)}")
    end
  end

  defp extract_legislation_year(legislation_title) do
    case Regex.run(~r/(\d{4})/, legislation_title) do
      [_, year] -> String.to_integer(year)
      nil -> nil
    end
  end

  @doc """
  Find or create legislation from a string (public API for AI parser).

  Parses the legislation string to extract title, year, and type,
  then finds existing or creates new legislation record.

  Returns {:ok, legislation_record} or {:error, reason}
  """
  def find_or_create_legislation(legislation_str, actor \\ nil) when is_binary(legislation_str) do
    # Parse legislation string to extract components
    year = extract_legislation_year(legislation_str)
    type = if String.contains?(legislation_str, "Regulation"), do: :regulation, else: :act

    case find_or_create_legislation_record(legislation_str, year, type, actor) do
      {:ok, legislation_id} ->
        # Return the full legislation record
        Ash.get(EhsEnforcement.Enforcement.Legislation, legislation_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_or_create_legislation_record(title, year, type, actor) do
    # Normalize title
    normalized_title = Utility.normalize_legislation_title(title)

    # Determine type code based on legislation type
    type_code = get_legislation_type_code(type, title)

    # Try to find existing
    case LegislationMatcher.find_or_create_legislation(normalized_title, year, nil, actor) do
      {:ok, legislation_id} when not is_nil(legislation_id) ->
        {:ok, legislation_id}

      {:ok, nil} ->
        # Create new legislation record
        attrs = %{
          legislation_title: normalized_title,
          legislation_year: year,
          legislation_type: type,
          legislation_type_code: type_code,
          legislation_url: build_legislation_url(type_code, year, title)
        }

        case Ash.create(EhsEnforcement.Enforcement.Legislation, attrs, actor: actor) do
          {:ok, legislation} -> {:ok, legislation.id}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_legislation_type_code(:act, title) do
    # Check for Scottish/Welsh Acts
    cond do
      String.contains?(title, "(Scotland)") -> "asp"
      String.contains?(title, "(Wales)") -> "anaw"
      true -> "ukpga"
    end
  end

  defp get_legislation_type_code(:regulation, title) do
    # Check for Scottish/Welsh SIs
    cond do
      String.contains?(title, "(Scotland)") -> "ssi"
      String.contains?(title, "(Wales)") -> "wsi"
      true -> "uksi"
    end
  end

  defp get_legislation_type_code(_, _), do: nil

  defp build_legislation_url(nil, _, _), do: nil

  defp build_legislation_url(_type_code, year, _title) when is_nil(year), do: nil

  defp build_legislation_url(type_code, year, _title) do
    # Can't determine number from title, just provide base URL pattern
    "https://www.legislation.gov.uk/#{type_code}/#{year}"
  end
end
