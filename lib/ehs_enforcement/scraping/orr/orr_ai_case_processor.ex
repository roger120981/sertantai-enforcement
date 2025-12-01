defmodule EhsEnforcement.Scraping.Orr.OrrAiCaseProcessor do
  @moduledoc """
  Processes AI-parsed ORR prosecution cases and creates database records.

  Transforms `OrrAiPdfParser.ParsedCase` structs into Ash resource records,
  handling the creation of:
  - Case records
  - Offender records (with lookup/create)
  - Offence records linking Cases to Legislation

  ## Usage

      alias EhsEnforcement.Scraping.Orr.{OrrAiPdfParser, OrrAiCaseProcessor}

      {:ok, parsed_cases} = OrrAiPdfParser.scrape_pdf_year(2012)
      {:ok, results} = OrrAiCaseProcessor.process_cases(parsed_cases, actor)
  """

  require Logger

  alias EhsEnforcement.Enforcement.Agency
  alias EhsEnforcement.Enforcement.Case
  alias EhsEnforcement.Enforcement.Offence
  alias EhsEnforcement.Enforcement.Offender
  alias EhsEnforcement.Scraping.Orr.OrrAiPdfParser.ParsedCase

  @doc """
  Process an AI-parsed case and create database records.

  Creates Case, Offender, and Offence records from a ParsedCase struct.

  Returns {:ok, case_record} or {:error, reason}
  """
  def process_and_create_case(%ParsedCase{} = parsed_case, actor \\ nil) do
    Logger.debug("ORR AI: Processing case for #{parsed_case.company_name}")

    with {:ok, agency} <- get_orr_agency(),
         {:ok, offender} <- find_or_create_offender(parsed_case, agency),
         {:ok, case_record} <- create_case(parsed_case, agency, offender, actor),
         {:ok, _offences} <- create_offence_records(case_record, parsed_case.legislation, actor) do
      {:ok, case_record}
    end
  end

  @doc """
  Process multiple AI-parsed cases.

  Returns {:ok, results} with created/existing/error counts.
  """
  def process_cases(parsed_cases, actor \\ nil) when is_list(parsed_cases) do
    results =
      Enum.reduce(parsed_cases, %{created: [], existing: [], errors: []}, fn parsed_case, acc ->
        case process_and_create_case(parsed_case, actor) do
          {:ok, case_record} ->
            %{acc | created: [case_record | acc.created]}

          {:error, %Ash.Error.Invalid{errors: errors}} = error ->
            if duplicate_error?(errors) do
              %{acc | existing: [parsed_case | acc.existing]}
            else
              Logger.warning("ORR AI: Error creating case: #{inspect(error)}")
              %{acc | errors: [{parsed_case, error} | acc.errors]}
            end

          {:error, reason} = error ->
            Logger.warning("ORR AI: Error processing case: #{inspect(reason)}")
            %{acc | errors: [{parsed_case, error} | acc.errors]}
        end
      end)

    {:ok, results}
  end

  @doc """
  Scrape all PDF prosecutions and save to database.

  This is the main entry point for PDF scraping with database persistence.

  Returns {:ok, results} or {:error, reason}
  """
  def scrape_and_save_all_pdfs(actor \\ nil) do
    alias EhsEnforcement.Scraping.Orr.OrrAiPdfParser

    Logger.info("ORR AI: Starting full PDF scrape and save")

    # scrape_all_pdfs always returns {:ok, cases}
    {:ok, parsed_cases} = OrrAiPdfParser.scrape_all_pdfs()
    Logger.info("ORR AI: Parsed #{length(parsed_cases)} cases from PDFs, saving to database")
    process_cases(parsed_cases, actor)
  end

  @doc """
  Scrape PDF prosecutions for a specific year and save to database.

  Returns {:ok, results} or {:error, reason}
  """
  def scrape_and_save_year(year, actor \\ nil) when is_integer(year) do
    alias EhsEnforcement.Scraping.Orr.OrrAiPdfParser

    Logger.info("ORR AI: Scraping and saving PDFs for year #{year}")

    # scrape_pdf_year always returns {:ok, cases}
    {:ok, parsed_cases} = OrrAiPdfParser.scrape_pdf_year(year)
    Logger.info("ORR AI: Parsed #{length(parsed_cases)} cases for #{year}")
    process_cases(parsed_cases, actor)
  end

  # Private functions

  defp get_orr_agency do
    case Ash.get(Agency, code: "orr") do
      {:ok, agency} -> {:ok, agency}
      {:error, _} -> {:error, :agency_not_found}
    end
  end

  defp find_or_create_offender(%ParsedCase{} = parsed_case, agency) do
    name = parsed_case.company_name

    # Try to find existing offender by name
    case find_offender_by_name(name) do
      {:ok, offender} ->
        # Update agencies list if needed
        _ = update_offender_agencies(offender, agency)
        {:ok, offender}

      {:error, :not_found} ->
        # Create new offender
        create_offender(parsed_case, agency)
    end
  end

  defp find_offender_by_name(name) do
    require Ash.Query

    query =
      Offender
      |> Ash.Query.filter(name == ^name)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [offender]} -> {:ok, offender}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_offender(%ParsedCase{} = parsed_case, agency) do
    Logger.info("Creating offender: #{parsed_case.company_name}")

    offender_params = %{
      name: parsed_case.company_name,
      postcode: nil,
      address: parsed_case.location,
      agencies: [agency.name]
    }

    case Ash.create(Offender, offender_params) do
      {:ok, offender} ->
        Logger.info("Created offender: #{offender.name} (ID: #{offender.id})")
        {:ok, offender}

      {:error, reason} ->
        Logger.error("Failed to create offender: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_offender_agencies(offender, agency) do
    current_agencies = offender.agencies || []

    unless agency.name in current_agencies do
      updated_agencies = [agency.name | current_agencies]

      case Ash.update(offender, %{agencies: updated_agencies}) do
        {:ok, updated} ->
          Logger.info(
            "Updated agencies for offender #{offender.name}: #{inspect(updated_agencies)}"
          )

          {:ok, updated}

        {:error, reason} ->
          Logger.warning("Failed to update offender agencies: #{inspect(reason)}")
          {:ok, offender}
      end
    else
      {:ok, offender}
    end
  end

  defp create_case(%ParsedCase{} = parsed_case, agency, offender, _actor) do
    regulator_id = generate_regulator_id(parsed_case)

    Logger.debug("ORR AI: Creating case from AI-parsed data: #{regulator_id}")

    # Build case params using correct Case resource field names
    case_params = %{
      agency_id: agency.id,
      offender_id: offender.id,
      regulator_id: regulator_id,
      offence_hearing_date: parsed_case.sentencing_date,
      offence_result: parsed_case.result || "Prosecution",
      offence_action_type: :prosecution,
      offence_fine: parsed_case.fine_amount,
      offence_costs: parsed_case.costs_amount,
      url: parsed_case.source_url || build_source_url()
    }

    case Ash.create(Case, case_params) do
      {:ok, case_record} ->
        Logger.info("ORR AI: Created case: #{regulator_id}")
        {:ok, case_record}

      {:error, reason} ->
        Logger.error("ORR AI: Failed to create case: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_offence_records(case_record, legislation_list, actor)
       when is_list(legislation_list) and length(legislation_list) > 0 do
    Logger.debug(
      "ORR AI: Creating #{length(legislation_list)} offence records for case #{case_record.id}"
    )

    offences =
      legislation_list
      |> Enum.map(fn legislation_str ->
        create_single_offence(case_record, legislation_str, actor)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, offences}
  end

  defp create_offence_records(case_record, _legislation, _actor) do
    Logger.debug("ORR AI: No legislation to link for case #{case_record.id}")
    {:ok, []}
  end

  defp create_single_offence(case_record, legislation_str, _actor)
       when is_binary(legislation_str) do
    case find_or_create_legislation(legislation_str) do
      {:ok, legislation} ->
        offence_params = %{
          case_id: case_record.id,
          legislation_id: legislation.id,
          offence_description: "Rail safety violation"
        }

        case Ash.create(Offence, offence_params) do
          {:ok, offence} ->
            Logger.debug("ORR AI: Created offence #{offence.id} for case #{case_record.id}")
            offence

          {:error, reason} ->
            Logger.warning("ORR AI: Failed to create offence: #{inspect(reason)}")
            nil
        end

      {:error, reason} ->
        Logger.warning(
          "ORR AI: Failed to find/create legislation '#{legislation_str}': #{inspect(reason)}"
        )

        nil
    end
  end

  defp create_single_offence(_case_record, _legislation, _actor), do: nil

  @doc """
  Find existing legislation or create a new record.

  Searches for legislation by title match, or creates with "Other Legislation" category.
  """
  def find_or_create_legislation(legislation_str) when is_binary(legislation_str) do
    alias EhsEnforcement.Enforcement.Legislation

    require Ash.Query

    # Normalize the search string
    normalized = String.trim(legislation_str)

    # Try exact title match first
    query =
      Legislation
      |> Ash.Query.filter(title == ^normalized)
      |> Ash.Query.limit(1)

    case Ash.read(query) do
      {:ok, [legislation]} ->
        {:ok, legislation}

      {:ok, []} ->
        # Try partial match
        find_by_partial_match(normalized)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_by_partial_match(legislation_str) do
    alias EhsEnforcement.Enforcement.Legislation

    require Ash.Query

    # Common ORR legislation patterns
    patterns = [
      {"Health and Safety at Work", "Health and Safety at Work etc Act 1974"},
      {"HSWA", "Health and Safety at Work etc Act 1974"},
      {"Railways and Other Guided",
       "Railways and Other Guided Transport Systems (Safety) Regulations 2006"},
      {"ROGS", "Railways and Other Guided Transport Systems (Safety) Regulations 2006"},
      {"Work at Height", "Work at Height Regulations 2005"}
    ]

    # Find matching pattern
    matched_title =
      Enum.find_value(patterns, fn {pattern, title} ->
        if String.contains?(String.downcase(legislation_str), String.downcase(pattern)) do
          title
        else
          nil
        end
      end)

    if matched_title do
      query =
        Legislation
        |> Ash.Query.filter(title == ^matched_title)
        |> Ash.Query.limit(1)

      case Ash.read(query) do
        {:ok, [legislation]} -> {:ok, legislation}
        {:ok, []} -> create_legislation(matched_title)
        {:error, reason} -> {:error, reason}
      end
    else
      # Create with original string
      create_legislation(legislation_str)
    end
  end

  defp create_legislation(title) do
    alias EhsEnforcement.Enforcement.Legislation

    Logger.info("ORR AI: Creating legislation: #{title}")

    params = %{
      title: title,
      category: "Other Legislation"
    }

    case Ash.create(Legislation, params) do
      {:ok, legislation} ->
        Logger.info("ORR AI: Created legislation: #{legislation.title}")
        {:ok, legislation}

      {:error, reason} ->
        Logger.error("ORR AI: Failed to create legislation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_regulator_id(%ParsedCase{} = parsed_case) do
    # Format: orr_{year}_{company_slug}_{date}
    company_slug =
      parsed_case.company_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.slice(0, 30)

    date_suffix =
      case parsed_case.sentencing_date do
        %Date{} = date -> Calendar.strftime(date, "%Y%m%d")
        _ -> "00000000"
      end

    "orr_#{parsed_case.year}_#{company_slug}_#{date_suffix}"
  end

  defp build_source_url do
    "https://www.orr.gov.uk/monitoring-regulation/rail/promoting-health-safety/investigation-enforcement-powers/our-enforcement-action-date/prosecutions"
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
