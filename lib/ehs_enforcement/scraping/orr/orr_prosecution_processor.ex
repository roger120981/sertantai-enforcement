defmodule EhsEnforcement.Scraping.Orr.OrrProsecutionProcessor do
  @moduledoc """
  ORR prosecution processing pipeline - transforms scraped data for Ash resource creation.

  Handles:
  - Data transformation from ORR website format to Case resource format
  - Offender creation/lookup
  - Deterministic regulator_id generation for deduplication

  ## Data Flow

  ```
  ScrapedProsecution
    → ProcessedProsecution
      → Case (with Offender, Agency)
  ```

  ## Legislation Mapping

  Common ORR legislation:
  - Health and Safety at Work etc Act 1974 (ukpga/1974/37)
  - Railways and Other Guided Transport Systems (Safety) Regulations 2006 (uksi/2006/599)
  - Work at Height Regulations 2005 (uksi/2005/735)
  """

  require Logger

  alias EhsEnforcement.Scraping.Orr.OrrProsecutionScraper.ScrapedProsecution

  @orr_agency_code :orr

  defmodule ProcessedProsecution do
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
  Process a single scraped prosecution into format ready for Ash Case resource creation.

  Returns {:ok, %ProcessedProsecution{}} or {:error, reason}
  """
  def process_prosecution(%ScrapedProsecution{} = prosecution) do
    Logger.debug("ORR: Processing prosecution for #{prosecution.company}")

    try do
      # Generate deterministic regulator_id for deduplication
      regulator_id = generate_regulator_id(prosecution)

      # Parse dates
      sentencing_date = parse_date(prosecution.sentencing_date)
      offence_date = parse_date(prosecution.date_of_offence)

      # Build offence result text (includes summary, result, sentences)
      offence_result = build_offence_result(prosecution)

      # Build offence breaches text (court + legislation)
      offence_breaches = build_offence_breaches(prosecution)

      processed = %ProcessedProsecution{
        regulator_id: regulator_id,
        agency_code: @orr_agency_code,
        offender_attrs: build_offender_attrs(prosecution),
        offence_hearing_date: sentencing_date,
        offence_action_date: offence_date,
        offence_fine: prosecution.penalty_amount,
        offence_costs: prosecution.costs_amount,
        offence_result: offence_result,
        offence_breaches: offence_breaches,
        offence_action_type: "ORR Prosecution",
        url: build_source_url(),
        source_metadata: build_source_metadata(prosecution)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("ORR: Failed to process prosecution: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped prosecutions in batch.

  Returns {:ok, [%ProcessedProsecution{}]} or {:ok, [%ProcessedProsecution{}], errors: [...]}
  """
  def process_prosecutions(scraped_prosecutions) when is_list(scraped_prosecutions) do
    Logger.info("ORR: Processing #{length(scraped_prosecutions)} scraped prosecutions")

    {processed, errors} =
      Enum.reduce(scraped_prosecutions, {[], []}, fn prosecution, {proc_acc, err_acc} ->
        case process_prosecution(prosecution) do
          {:ok, processed_prosecution} ->
            {[processed_prosecution | proc_acc], err_acc}

          {:error, reason} ->
            identifier = "#{prosecution.company}@#{prosecution.year}"
            {proc_acc, [{identifier, reason} | err_acc]}
        end
      end)

    processed_list = Enum.reverse(processed)

    if errors == [] do
      Logger.info("ORR: Successfully processed all #{length(processed_list)} prosecutions")
      {:ok, processed_list}
    else
      Logger.warning(
        "ORR: Processed #{length(processed_list)} prosecutions with #{length(errors)} errors"
      )

      {:ok, processed_list, errors: Enum.reverse(errors)}
    end
  end

  @doc """
  Create a Case from processed data using Ash patterns.

  Returns {:ok, %Case{}} or {:error, reason}
  """
  def create_case_from_processed(%ProcessedProsecution{} = processed, actor) do
    Logger.debug("ORR: Creating case from processed data: #{processed.regulator_id}")

    # Get ORR agency
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
                  Logger.debug("ORR: Case already exists: #{processed.regulator_id}")
                  {:ok, :duplicate}
                else
                  Logger.error("ORR: Failed to create case: #{inspect(ash_error)}")
                  {:error, ash_error}
                end

              {:error, reason} ->
                Logger.error("ORR: Failed to create case: #{inspect(reason)}")
                {:error, {:case_creation_error, reason}}
            end

          {:error, reason} ->
            Logger.error("ORR: Failed to find/create offender: #{inspect(reason)}")
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
  def process_and_create_prosecution(%ScrapedProsecution{} = prosecution, actor) do
    case process_prosecution(prosecution) do
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
  def process_and_create_all(scraped_prosecutions, actor) when is_list(scraped_prosecutions) do
    Logger.info("ORR: Processing and creating #{length(scraped_prosecutions)} prosecutions")

    results =
      Enum.reduce(scraped_prosecutions, %{created: 0, duplicates: 0, errors: []}, fn prosecution,
                                                                                     acc ->
        case process_and_create_prosecution(prosecution, actor) do
          {:ok, :duplicate} ->
            %{acc | duplicates: acc.duplicates + 1}

          {:ok, _case} ->
            %{acc | created: acc.created + 1}

          {:error, reason} ->
            identifier = "#{prosecution.company}@#{prosecution.year}"
            %{acc | errors: [{identifier, reason} | acc.errors]}
        end
      end)

    Logger.info(
      "ORR: Created #{results.created}, duplicates #{results.duplicates}, errors #{length(results.errors)}"
    )

    {:ok, results}
  end

  # Private Functions

  defp generate_regulator_id(prosecution) do
    # Format: orr_{year}_{company_slug}_{sentencing_date}
    # Deterministic for deduplication

    year = prosecution.year || 0

    company_slug =
      (prosecution.company || "unknown")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.slice(0, 40)
      |> String.trim("_")

    date_part =
      case parse_date(prosecution.sentencing_date) do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    "orr_#{year}_#{company_slug}_#{date_part}"
  end

  defp build_offender_attrs(prosecution) do
    %{
      name: prosecution.company || "[Unknown Company]",
      address: prosecution.location,
      country: "United Kingdom"
    }
  end

  defp build_offence_result(prosecution) do
    parts = []

    # Add summary
    parts =
      if prosecution.summary && String.length(prosecution.summary) > 0 do
        [prosecution.summary | parts]
      else
        parts
      end

    # Add result
    parts =
      if prosecution.result && String.length(prosecution.result) > 0 do
        ["Result: #{prosecution.result}" | parts]
      else
        parts
      end

    # Add plea
    parts =
      if prosecution.plea && String.length(prosecution.plea) > 0 do
        ["Plea: #{prosecution.plea}" | parts]
      else
        parts
      end

    # Add penalty details (for culpability category info)
    parts =
      if prosecution.penalty && String.length(prosecution.penalty) > 0 &&
           String.contains?(prosecution.penalty, ["culpability", "Category", "Organisation"]) do
        ["Penalty category: #{prosecution.penalty}" | parts]
      else
        parts
      end

    parts
    |> Enum.reverse()
    |> Enum.join("\n\n")
    |> String.trim()
  end

  defp build_offence_breaches(prosecution) do
    parts = []

    # Add court
    parts =
      if prosecution.court && String.length(prosecution.court) > 0 do
        ["Court: #{prosecution.court}" | parts]
      else
        parts
      end

    # Add breaches/legislation
    parts =
      if prosecution.breaches_involved && String.length(prosecution.breaches_involved) > 0 do
        ["Breaches: #{prosecution.breaches_involved}" | parts]
      else
        parts
      end

    parts
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp build_source_url do
    "https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prosecutions"
  end

  defp build_source_metadata(prosecution) do
    %{
      scraped_at: prosecution.scrape_timestamp,
      scraper_version: "1.0",
      source: "orr.gov.uk",
      year: prosecution.year,
      company: prosecution.company,
      court: prosecution.court,
      penalty_raw: prosecution.penalty,
      costs_raw: prosecution.costs,
      location: prosecution.location,
      orr_details: prosecution.orr_details
    }
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    # Common formats:
    # "3 October 2025"
    # "14 February 2025"
    # "On and before 1st December 2018" -> extract the date

    # Clean up ordinal suffixes
    cleaned =
      date_string
      |> String.replace(~r/(\d+)(?:st|nd|rd|th)/, "\\1")
      |> String.replace(~r/^On and before\s+/i, "")
      |> String.replace(~r/^Before\s+/i, "")
      |> String.trim()

    # Try to parse "DD Month YYYY"
    case Regex.run(~r/(\d{1,2})\s+(\w+)\s+(\d{4})/, cleaned) do
      [_, day, month, year] ->
        month_num = month_to_number(month)

        if month_num do
          case Date.new(
                 String.to_integer(year),
                 month_num,
                 String.to_integer(day)
               ) do
            {:ok, date} -> date
            _ -> nil
          end
        else
          nil
        end

      nil ->
        nil
    end
  end

  defp parse_date(_), do: nil

  defp month_to_number(month) do
    months = %{
      "january" => 1,
      "february" => 2,
      "march" => 3,
      "april" => 4,
      "may" => 5,
      "june" => 6,
      "july" => 7,
      "august" => 8,
      "september" => 9,
      "october" => 10,
      "november" => 11,
      "december" => 12
    }

    Map.get(months, String.downcase(month))
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
