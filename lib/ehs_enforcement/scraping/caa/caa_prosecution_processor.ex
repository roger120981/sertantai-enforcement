defmodule EhsEnforcement.Scraping.Caa.CaaProsecutionProcessor do
  @moduledoc """
  CAA prosecution processing pipeline - transforms scraped data for Ash resource creation.

  Handles:
  - Data transformation from CAA PDF format to Case resource format
  - Offender creation/lookup
  - Deterministic regulator_id generation for deduplication

  ## Data Flow

  ```
  ScrapedProsecution
    → ProcessedProsecution
      → Case (with Offender, Agency)
  ```

  ## Legislation Mapping

  Common CAA offences relate to:
  - Civil Aviation Act 1982 (ukpga/1982/16)
  - Air Navigation Order 2016 (uksi/2016/765)
  - Air Navigation (Amendment) Order 2018 (uksi/2018/623)
  """

  require Logger

  alias EhsEnforcement.Scraping.Caa.CaaProsecutionScraper.ScrapedProsecution

  @caa_agency_code :caa

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
    Logger.debug("CAA: Processing prosecution for #{prosecution.defendant}")

    try do
      # Generate deterministic regulator_id for deduplication
      regulator_id = generate_regulator_id(prosecution)

      # Parse dates
      hearing_date = parse_date(prosecution.date)

      # Build offence result text
      offence_result = build_offence_result(prosecution)

      # Build offence breaches text (court + description)
      offence_breaches = build_offence_breaches(prosecution)

      processed = %ProcessedProsecution{
        regulator_id: regulator_id,
        agency_code: @caa_agency_code,
        offender_attrs: build_offender_attrs(prosecution),
        offence_hearing_date: hearing_date,
        offence_action_date: hearing_date,
        offence_fine: prosecution.fine_amount,
        offence_costs: nil,
        offence_result: offence_result,
        offence_breaches: offence_breaches,
        offence_action_type: "CAA Prosecution",
        url: build_source_url(),
        source_metadata: build_source_metadata(prosecution)
      }

      {:ok, processed}
    rescue
      error ->
        Logger.error("CAA: Failed to process prosecution: #{inspect(error)}")
        {:error, {:processing_error, error}}
    end
  end

  @doc """
  Process multiple scraped prosecutions in batch.

  Returns {:ok, [%ProcessedProsecution{}]} or {:ok, [%ProcessedProsecution{}], errors: [...]}
  """
  def process_prosecutions(scraped_prosecutions) when is_list(scraped_prosecutions) do
    Logger.info("CAA: Processing #{length(scraped_prosecutions)} scraped prosecutions")

    {processed, errors} =
      Enum.reduce(scraped_prosecutions, {[], []}, fn prosecution, {proc_acc, err_acc} ->
        case process_prosecution(prosecution) do
          {:ok, processed_prosecution} ->
            {[processed_prosecution | proc_acc], err_acc}

          {:error, reason} ->
            identifier = "#{prosecution.defendant}@#{prosecution.fiscal_year}"
            {proc_acc, [{identifier, reason} | err_acc]}
        end
      end)

    processed_list = Enum.reverse(processed)

    if errors == [] do
      Logger.info("CAA: Successfully processed all #{length(processed_list)} prosecutions")
      {:ok, processed_list}
    else
      Logger.warning(
        "CAA: Processed #{length(processed_list)} prosecutions with #{length(errors)} errors"
      )

      {:ok, processed_list, errors: Enum.reverse(errors)}
    end
  end

  @doc """
  Create a Case from processed data using Ash patterns.

  Returns {:ok, %Case{}} or {:error, reason}
  """
  def create_case_from_processed(%ProcessedProsecution{} = processed, actor) do
    Logger.debug("CAA: Creating case from processed data: #{processed.regulator_id}")

    # Get CAA agency
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
                  Logger.debug("CAA: Case already exists: #{processed.regulator_id}")
                  {:ok, :duplicate}
                else
                  Logger.error("CAA: Failed to create case: #{inspect(ash_error)}")
                  {:error, ash_error}
                end

              {:error, reason} ->
                Logger.error("CAA: Failed to create case: #{inspect(reason)}")
                {:error, {:case_creation_error, reason}}
            end

          {:error, reason} ->
            Logger.error("CAA: Failed to find/create offender: #{inspect(reason)}")
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
    Logger.info("CAA: Processing and creating #{length(scraped_prosecutions)} prosecutions")

    results =
      Enum.reduce(scraped_prosecutions, %{created: 0, duplicates: 0, errors: []}, fn prosecution,
                                                                                     acc ->
        case process_and_create_prosecution(prosecution, actor) do
          {:ok, :duplicate} ->
            %{acc | duplicates: acc.duplicates + 1}

          {:ok, _case} ->
            %{acc | created: acc.created + 1}

          {:error, reason} ->
            identifier = "#{prosecution.defendant}@#{prosecution.fiscal_year}"
            %{acc | errors: [{identifier, reason} | acc.errors]}
        end
      end)

    Logger.info(
      "CAA: Created #{results.created}, duplicates #{results.duplicates}, errors #{length(results.errors)}"
    )

    {:ok, results}
  end

  # Private Functions

  defp generate_regulator_id(prosecution) do
    # Format: caa_{fiscal_year}_{defendant_slug}_{date}
    # Deterministic for deduplication

    fiscal_year =
      (prosecution.fiscal_year || "unknown")
      |> String.replace("-", "")

    defendant_slug =
      (prosecution.defendant || "unknown")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.slice(0, 40)
      |> String.trim("_")

    date_part =
      case parse_date(prosecution.date) do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    "caa_#{fiscal_year}_#{defendant_slug}_#{date_part}"
  end

  defp build_offender_attrs(prosecution) do
    %{
      name: prosecution.defendant || "[Unknown Defendant]",
      country: "United Kingdom"
    }
  end

  defp build_offence_result(prosecution) do
    parts = []

    # Add brief description
    parts =
      if prosecution.brief_description && String.length(prosecution.brief_description) > 0 do
        [prosecution.brief_description | parts]
      else
        parts
      end

    # Add sentence
    parts =
      if prosecution.sentence && String.length(prosecution.sentence) > 0 do
        ["Sentence: #{prosecution.sentence}" | parts]
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

    parts
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp build_source_url do
    "https://www.caa.co.uk/our-work/about-us/enforcement/enforcement-and-prosecutions/"
  end

  defp build_source_metadata(prosecution) do
    %{
      scraped_at: prosecution.scrape_timestamp,
      scraper_version: "1.0",
      source: "caa.co.uk",
      fiscal_year: prosecution.fiscal_year,
      defendant: prosecution.defendant,
      court: prosecution.court,
      sentence_raw: prosecution.sentence
    }
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    # CAA dates are in DD/MM/YYYY format
    case Regex.run(~r/(\d{2})\/(\d{2})\/(\d{4})/, date_string) do
      [_, day, month, year] ->
        case Date.new(
               String.to_integer(year),
               String.to_integer(month),
               String.to_integer(day)
             ) do
          {:ok, date} -> date
          _ -> nil
        end

      nil ->
        nil
    end
  end

  defp parse_date(_), do: nil

  defp duplicate_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn error ->
      case error do
        %Ash.Error.Changes.InvalidChanges{message: msg} ->
          String.contains?(msg || "", "already exists")

        %{message: msg} when is_binary(msg) ->
          String.contains?(msg, "already exists") or
            String.contains?(msg, "has already been taken")

        _ ->
          false
      end
    end)
  end

  defp duplicate_error?(_), do: false
end
