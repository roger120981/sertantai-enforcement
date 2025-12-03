defmodule EhsEnforcement.Scraping.Api.CaaCoordinator do
  @moduledoc """
  Coordinator for CAA (Civil Aviation Authority) scraping operations.

  Provides the API entry point for triggering CAA scraping sessions,
  delegating to the AgencyBehavior implementation in Agencies.Caa.

  ## Usage

      # Start a full scrape of all data (prosecutions + undertakings)
      CaaCoordinator.start_scraping([])

      # Scrape only prosecutions
      CaaCoordinator.start_scraping(data_type: :prosecutions)

      # Scrape only undertakings
      CaaCoordinator.start_scraping(data_type: :undertakings)

      # Scrape specific fiscal years
      CaaCoordinator.start_scraping(years: ["2024-2025", "2023-2024"])

      # Use AI parsing for legacy format PDFs (2017-2022)
      CaaCoordinator.start_scraping(use_ai_parsing: true)
  """

  require Logger

  alias EhsEnforcement.Scraping.Agencies.Caa

  @doc """
  Start a CAA scraping session.

  ## Options

  - `:data_type` - :all, :prosecutions, or :undertakings (default: :all)
  - `:years` - List of fiscal years to scrape (e.g., ["2024-2025"])
  - `:use_ai_parsing` - Use AI for legacy PDFs (default: false)
  - `:actor` - Actor for Ash operations
  - `:scrape_type` - :manual or :scheduled (default: :manual)

  ## Returns

  - `{:ok, session}` - Scraping session completed/in progress
  - `{:error, reason}` - Failed to start or execute scraping
  """
  def start_scraping(opts \\ []) do
    Logger.info("CAA Coordinator: Starting scraping with options: #{inspect(opts)}")

    with {:ok, validated_params} <- Caa.validate_params(opts) do
      Caa.start_scraping(validated_params, %{})
    end
  end

  @doc """
  Scrape only CAA prosecutions.
  """
  def scrape_prosecutions(opts \\ []) do
    start_scraping(Keyword.put(opts, :data_type, :prosecutions))
  end

  @doc """
  Scrape only CAA undertakings.
  """
  def scrape_undertakings(opts \\ []) do
    start_scraping(Keyword.put(opts, :data_type, :undertakings))
  end

  @doc """
  Check if AI parsing is available for legacy format PDFs.
  """
  def ai_parsing_available? do
    Caa.ai_parsing_available?()
  end

  @doc """
  Start a quick test scrape with only the most recent year.
  """
  def test_scrape(opts \\ []) do
    test_opts = Keyword.merge([years: ["2024-2025"]], opts)
    start_scraping(test_opts)
  end
end
