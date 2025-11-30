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
end
