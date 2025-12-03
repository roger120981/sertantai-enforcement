defmodule EhsEnforcement.Scraping.Api.OrrCoordinator do
  @moduledoc """
  Coordinator for ORR (Office of Rail and Road) scraping operations.

  Provides the API entry point for triggering ORR scraping sessions,
  delegating to the AgencyBehavior implementation in Agencies.Orr.

  ## Usage

      # Start a full scrape of all data (prosecutions + notices)
      OrrCoordinator.start_scraping([])

      # Scrape only prosecutions
      OrrCoordinator.start_scraping(data_type: :prosecutions)

      # Scrape only notices
      OrrCoordinator.start_scraping(data_type: :notices)

      # Scrape specific notice type
      OrrCoordinator.start_scraping(data_type: :notices, notice_type: :improvement)

      # Scrape specific years
      OrrCoordinator.start_scraping(years: [2024, 2023])
  """

  require Logger

  alias EhsEnforcement.Scraping.Agencies.Orr

  @doc """
  Start an ORR scraping session.

  ## Options

  - `:data_type` - :all, :prosecutions, or :notices (default: :all)
  - `:years` - List of years to scrape (default: all available)
  - `:notice_type` - :improvement, :prohibition, or nil for both (default: nil)
  - `:actor` - Actor for Ash operations
  - `:scrape_type` - :manual or :scheduled (default: :manual)

  ## Returns

  - `{:ok, session}` - Scraping session completed/in progress
  - `{:error, reason}` - Failed to start or execute scraping
  """
  def start_scraping(opts \\ []) do
    Logger.info("ORR Coordinator: Starting scraping with options: #{inspect(opts)}")

    with {:ok, validated_params} <- Orr.validate_params(opts) do
      Orr.start_scraping(validated_params, %{})
    end
  end

  @doc """
  Scrape only ORR prosecutions.
  """
  def scrape_prosecutions(opts \\ []) do
    start_scraping(Keyword.put(opts, :data_type, :prosecutions))
  end

  @doc """
  Scrape only ORR notices.
  """
  def scrape_notices(opts \\ []) do
    start_scraping(Keyword.put(opts, :data_type, :notices))
  end

  @doc """
  Scrape only improvement notices.
  """
  def scrape_improvement_notices(opts \\ []) do
    opts
    |> Keyword.put(:data_type, :notices)
    |> Keyword.put(:notice_type, :improvement)
    |> start_scraping()
  end

  @doc """
  Scrape only prohibition notices.
  """
  def scrape_prohibition_notices(opts \\ []) do
    opts
    |> Keyword.put(:data_type, :notices)
    |> Keyword.put(:notice_type, :prohibition)
    |> start_scraping()
  end

  @doc """
  Get available years for improvement notices.
  """
  def improvement_years do
    EhsEnforcement.Scraping.Orr.OrrNoticeScraper.improvement_years()
  end

  @doc """
  Get available years for prohibition notices.
  """
  def prohibition_years do
    EhsEnforcement.Scraping.Orr.OrrNoticeScraper.prohibition_years()
  end

  @doc """
  Start a quick test scrape with only the most recent year.
  """
  def test_scrape(opts \\ []) do
    test_opts = Keyword.merge([years: [2024]], opts)
    start_scraping(test_opts)
  end
end
