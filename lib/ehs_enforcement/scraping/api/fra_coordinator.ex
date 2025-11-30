defmodule EhsEnforcement.Scraping.Api.FraCoordinator do
  @moduledoc """
  Coordinator for FRA (Fire and Rescue Authorities) scraping operations.

  Provides the API entry point for triggering FRA scraping sessions,
  delegating to the AgencyBehavior implementation in Agencies.Fra.

  ## Usage

      # Start a full scrape of all notices
      FraCoordinator.start_scraping([])

      # Scrape only Prohibition notices
      FraCoordinator.start_scraping(notice_type: "PROHIBITION")

      # Scrape with page limit for testing
      FraCoordinator.start_scraping(max_pages: 1, page_size: 10)

      # Scrape for specific Fire & Rescue Service
      FraCoordinator.start_scraping(frs: "West Yorkshire")
  """

  require Logger

  alias EhsEnforcement.Scraping.Agencies.Fra

  @doc """
  Start a FRA scraping session.

  ## Options

  - `:notice_type` - Filter by notice type: "PROHIBITION", "ENFORCEMENT", "ALTERATIONS"
  - `:frs` - Filter by Fire & Rescue Service name
  - `:status` - Filter by status: "IN FORCE", "COMPLIED"
  - `:page_size` - Records per page (default: 100)
  - `:max_pages` - Maximum pages to fetch (nil = all)
  - `:actor` - Actor for Ash operations
  - `:scrape_type` - :manual or :scheduled (default: :manual)

  ## Returns

  - `{:ok, session}` - Scraping session completed/in progress
  - `{:error, reason}` - Failed to start or execute scraping
  """
  def start_scraping(opts \\ []) do
    Logger.info("FRA Coordinator: Starting scraping with options: #{inspect(opts)}")

    with {:ok, validated_params} <- Fra.validate_params(opts) do
      Fra.start_scraping(validated_params, %{})
    end
  end

  @doc """
  Get the total count of notices in the NFCC register.

  Useful for estimating scraping time or showing progress.
  """
  def get_total_count do
    EhsEnforcement.Scraping.Fra.FraNoticeScraper.get_total_count()
  end

  @doc """
  Start a quick test scrape with limited pages.

  Useful for testing the scraper without fetching all ~7,700 records.
  """
  def test_scrape(opts \\ []) do
    test_opts =
      Keyword.merge(
        [max_pages: 1, page_size: 10],
        opts
      )

    start_scraping(test_opts)
  end
end
