defmodule EhsEnforcement.Scraping.Api.OpssCoordinator do
  @moduledoc """
  Coordinator for OPSS (Office for Product Safety and Standards) scraping operations.

  Provides the API entry point for triggering OPSS scraping sessions,
  delegating to the AgencyBehavior implementation in Agencies.Opss.

  ## Usage

      # Start a full scrape of all data (notices + prosecutions)
      OpssCoordinator.start_scraping([])

      # Scrape only notices
      OpssCoordinator.start_scraping(data_type: :notices)

      # Scrape only prosecutions
      OpssCoordinator.start_scraping(data_type: :prosecutions)

      # Scrape specific periods
      OpssCoordinator.start_scraping(periods: ["april-2024-to-september-2024"])
  """

  require Logger

  alias EhsEnforcement.Scraping.Agencies.Opss

  @doc """
  Start an OPSS scraping session.

  ## Options

  - `:data_type` - :all, :notices, or :prosecutions (default: :all)
  - `:periods` - List of periods to scrape (default: all available)
  - `:actor` - Actor for Ash operations
  - `:scrape_type` - :manual or :scheduled (default: :manual)

  ## Returns

  - `{:ok, session}` - Scraping session completed/in progress
  - `{:error, reason}` - Failed to start or execute scraping
  """
  def start_scraping(opts \\ []) do
    Logger.info("OPSS Coordinator: Starting scraping with options: #{inspect(opts)}")

    with {:ok, validated_params} <- Opss.validate_params(opts) do
      Opss.start_scraping(validated_params, %{})
    end
  end

  @doc """
  Scrape only OPSS notices.
  """
  def scrape_notices(opts \\ []) do
    start_scraping(Keyword.put(opts, :data_type, :notices))
  end

  @doc """
  Scrape only OPSS prosecutions.
  """
  def scrape_prosecutions(opts \\ []) do
    start_scraping(Keyword.put(opts, :data_type, :prosecutions))
  end

  @doc """
  Get available scraping periods.
  """
  def available_periods do
    EhsEnforcement.Scraping.Opss.OpssEnforcementScraper.available_periods()
  end

  @doc """
  Start a quick test scrape with only the most recent period.
  """
  def test_scrape(opts \\ []) do
    periods = available_periods()
    most_recent = List.first(periods)

    test_opts = Keyword.merge([periods: [most_recent]], opts)
    start_scraping(test_opts)
  end
end
