defmodule EhsEnforcement.Scraping.Api.McaCoordinator do
  @moduledoc """
  Coordinator for MCA (Maritime and Coastguard Agency) scraping operations.

  Provides the API entry point for triggering MCA scraping sessions,
  delegating to the AgencyBehavior implementation in Agencies.Mca.

  ## Usage

      # Start a full scrape of all HTML years (2020-2025)
      McaCoordinator.start_scraping([])

      # Scrape specific years
      McaCoordinator.start_scraping(years: [2024, 2025])

      # Include PDF years (requires pdftotext)
      McaCoordinator.start_scraping(include_pdf_years: true)

      # Quick test scrape (most recent year only)
      McaCoordinator.test_scrape()

  ## Data Volume

  - HTML years (2020-2025): ~30-40 prosecutions total
  - PDF years (2010-2019): ~50-60 prosecutions total
  """

  require Logger

  alias EhsEnforcement.Scraping.Agencies.Mca

  @doc """
  Start an MCA scraping session.

  ## Options

  - `:years` - List of years to scrape (default: all HTML years 2020-2025)
  - `:include_pdf_years` - Include PDF years 2010-2019 (default: false)
  - `:actor` - Actor for Ash operations
  - `:scrape_type` - :manual or :scheduled (default: :manual)

  ## Returns

  - `{:ok, session}` - Scraping session completed/in progress
  - `{:error, reason}` - Failed to start or execute scraping
  """
  def start_scraping(opts \\ []) do
    Logger.info("MCA Coordinator: Starting scraping with options: #{inspect(opts)}")

    with {:ok, validated_params} <- Mca.validate_params(opts) do
      Mca.start_scraping(validated_params, %{})
    end
  end

  @doc """
  Get available years for HTML scraping.

  Returns list of years that can be scraped without PDF extraction.
  """
  def available_html_years do
    EhsEnforcement.Scraping.Mca.McaProsecutionScraper.available_html_years()
  end

  @doc """
  Get the GOV.UK collection page URL.

  Returns the main page listing all MCA prosecution reports.
  """
  def collection_url do
    EhsEnforcement.Scraping.Mca.McaProsecutionScraper.collection_url()
  end

  @doc """
  Start a quick test scrape with only the most recent year.

  Useful for testing the scraper without fetching all years.
  """
  def test_scrape(opts \\ []) do
    most_recent_year = available_html_years() |> Enum.max()

    test_opts =
      Keyword.merge(
        [years: [most_recent_year]],
        opts
      )

    start_scraping(test_opts)
  end

  @doc """
  Scrape a single year.

  Useful for targeted scraping of a specific year's prosecutions.
  """
  def scrape_year(year, opts \\ []) when is_integer(year) do
    year_opts = Keyword.put(opts, :years, [year])
    start_scraping(year_opts)
  end

  @doc """
  Scrape all years including PDF (2010-2025).

  Requires `pdftotext` (poppler-utils) to be installed for PDF years.
  """
  def scrape_all_years(opts \\ []) do
    all_opts = Keyword.merge(opts, include_pdf_years: true, years: 2010..2025 |> Enum.to_list())
    start_scraping(all_opts)
  end

  @doc """
  Scrape PDF years (2010-2019) using AI parsing.

  Downloads PDFs from GOV.UK, extracts text with pdftotext, and uses
  LLM to parse narrative content into structured case data.

  ## Options

  - `:years` - List of years to scrape (default: 2010-2019)
  - `:actor` - Actor for Ash operations

  ## Returns

  - `{:ok, results}` with counts of created/existing/error cases
  - `{:error, reason}` on failure
  """
  def scrape_pdf_years(opts \\ []) do
    alias EhsEnforcement.Scraping.Mca.{McaAiPdfParser, McaAiCaseProcessor}

    years = Keyword.get(opts, :years, Enum.to_list(2010..2019))
    actor = Keyword.get(opts, :actor)

    Logger.info("MCA Coordinator: Starting AI-powered PDF scraping for years: #{inspect(years)}")

    # PDF URLs by year (these need to be fetched from publication pages)
    results =
      Enum.reduce(years, %{created: 0, existing: 0, errors: 0, year_errors: []}, fn year, acc ->
        Logger.info("MCA Coordinator: Processing PDF for year #{year}")

        case scrape_single_pdf_year(year, actor) do
          {:ok, year_results} ->
            %{
              acc
              | created: acc.created + length(year_results.created),
                existing: acc.existing + length(year_results.existing),
                errors: acc.errors + length(year_results.errors)
            }

          {:error, reason} ->
            Logger.warning("MCA Coordinator: Failed to process year #{year}: #{inspect(reason)}")
            %{acc | year_errors: [{year, reason} | acc.year_errors]}
        end
      end)

    Logger.info("MCA Coordinator: PDF scraping complete",
      created: results.created,
      existing: results.existing,
      errors: results.errors,
      year_errors: length(results.year_errors)
    )

    {:ok, results}
  end

  @doc """
  Scrape a single PDF year using AI parsing.
  """
  def scrape_single_pdf_year(year, actor \\ nil) when year in 2010..2019 do
    alias EhsEnforcement.Scraping.Mca.{McaAiPdfParser, McaAiCaseProcessor}

    # First, get the PDF URL from the publication page
    pub_url =
      "https://www.gov.uk/government/publications/mca-enforcement-unit-prosecutions-#{year}"

    Logger.info("MCA Coordinator: Fetching PDF URL from #{pub_url}")

    with {:ok, pdf_url} <- fetch_pdf_url_from_publication(pub_url),
         {:ok, parsed_cases} <- McaAiPdfParser.parse_pdf_url(pdf_url, year),
         {:ok, results} <- McaAiCaseProcessor.process_cases(parsed_cases, actor) do
      Logger.info(
        "MCA Coordinator: Year #{year} complete - #{length(results.created)} created, #{length(results.existing)} existing"
      )

      {:ok, results}
    end
  end

  defp fetch_pdf_url_from_publication(pub_url) do
    case Req.get(pub_url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        # Parse HTML to find PDF link
        {:ok, document} = Floki.parse_document(body)

        pdf_links =
          document
          |> Floki.find("a[href*='.pdf']")
          |> Enum.map(fn a -> Floki.attribute(a, "href") |> List.first() end)
          |> Enum.reject(&is_nil/1)

        case pdf_links do
          [pdf_url | _] ->
            full_url =
              if String.starts_with?(pdf_url, "http") do
                pdf_url
              else
                "https://www.gov.uk" <> pdf_url
              end

            {:ok, full_url}

          [] ->
            {:error, :pdf_not_found}
        end

      {:ok, %{status: 404}} ->
        {:error, {:not_found, pub_url}}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end
end
