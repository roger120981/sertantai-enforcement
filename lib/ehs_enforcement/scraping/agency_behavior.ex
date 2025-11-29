defmodule EhsEnforcement.Scraping.AgencyBehavior do
  @moduledoc """
  Behavior for agency-specific scraping implementations.

  This behavior defines a standard interface for implementing agency-specific
  scraping logic while maintaining consistency across different regulatory agencies.

  ## Implementation Requirements

  Each agency implementation must provide:

  1. **Parameter Validation** - Validate agency-specific requirements
  2. **Scraping Execution** - Execute the actual scraping with proper error handling
  3. **Result Processing** - Process and format results for the unified system

  ## Example Implementation

      defmodule EhsEnforcement.Scraping.Agencies.Hse do
        @behaviour EhsEnforcement.Scraping.AgencyBehavior

        @impl true
        def validate_params(opts) do
          # HSE-specific validation (requires start_page, end_page, database)
        end

        @impl true
        def start_scraping(validated_params, config) do
          # HSE-specific scraping logic using page-based iteration
        end

        @impl true
        def process_results(session_results) do
          # Process HSE results for unified return format
        end
      end

  ## Usage in ScrapeCoordinator

      def start_scraping_session(opts) do
        agency = Keyword.get(opts, :agency, :hse)
        agency_module = get_agency_module(agency)

        with {:ok, validated_params} <- agency_module.validate_params(opts),
             config <- load_scraping_config(opts),
             {:ok, results} <- agency_module.start_scraping(validated_params, config) do
          agency_module.process_results(results)
        end
      end
  """

  @doc """
  Validate agency-specific parameters for scraping.

  Each agency has different requirements:
  - HSE: requires start_page, end_page, database
  - EA: requires date_from, date_to, action_types

  ## Parameters

  - `opts` - Keyword list of scraping options from the user interface

  ## Returns

  - `{:ok, validated_params}` - Validated and normalized parameters
  - `{:error, reason}` - Validation error with descriptive message

  ## Example

      # HSE validation
      iex> Hse.validate_params([start_page: 1, end_page: 5, database: "convictions"])
      {:ok, %{start_page: 1, end_page: 5, database: "convictions", ...}}

      # EA validation
      iex> Ea.validate_params([date_from: ~D[2024-01-01], date_to: ~D[2024-01-31]])
      {:ok, %{date_from: ~D[2024-01-01], date_to: ~D[2024-01-31], ...}}
  """
  @callback validate_params(opts :: keyword()) :: {:ok, map()} | {:error, term()}

  @doc """
  Execute agency-specific scraping with validated parameters.

  This is the main scraping execution function that handles:
  - Creating the ScrapeSession record
  - Executing the agency-specific scraping logic
  - Handling errors and retries
  - Managing progress tracking

  ## Parameters

  - `validated_params` - Parameters validated by validate_params/1
  - `config` - Scraping configuration from load_scraping_config/1

  ## Returns

  - `{:ok, session_results}` - Completed session with results
  - `{:error, reason}` - Scraping error with descriptive message

  ## Example

      # After validation, execute scraping
      iex> validated_params = %{start_page: 1, end_page: 5, database: "convictions"}
      iex> config = %ScrapingConfig{max_pages_per_session: 100, ...}
      iex> Hse.start_scraping(validated_params, config)
      {:ok, %ScrapeSession{status: :completed, cases_created: 150, ...}}
  """
  @callback start_scraping(validated_params :: map(), config :: struct()) ::
              {:ok, struct()} | {:error, term()}

  @doc """
  Process scraping results for unified return format.

  This function handles any agency-specific post-processing of results
  and ensures consistent return format across all agencies.

  ## Parameters

  - `session_results` - The completed ScrapeSession struct from start_scraping/2

  ## Returns

  - `session_results` - Processed session results (may be unchanged)

  ## Example

      # Simple pass-through for most agencies
      iex> session = %ScrapeSession{status: :completed, cases_created: 150}
      iex> Hse.process_results(session)
      %ScrapeSession{status: :completed, cases_created: 150}
  """
  @callback process_results(session_results :: struct()) :: struct()

  @doc """
  Get the appropriate agency module for the given agency atom.

  ## Parameters

  - `agency` - Agency atom (:hse, :ea, etc.)

  ## Returns

  - Module implementing AgencyBehavior
  - Raises if agency not supported

  ## Example

      iex> get_agency_module(:hse)
      EhsEnforcement.Scraping.Agencies.Hse

      iex> get_agency_module(:ea)
      EhsEnforcement.Scraping.Agencies.Ea
  """
  def get_agency_module(:hse), do: EhsEnforcement.Scraping.Agencies.Hse
  def get_agency_module(:ea), do: EhsEnforcement.Scraping.Agencies.Ea
  def get_agency_module(:sepa), do: EhsEnforcement.Scraping.Agencies.Sepa
  # Alias for backward compatibility
  def get_agency_module(:environment_agency), do: EhsEnforcement.Scraping.Agencies.Ea

  def get_agency_module(agency) do
    raise ArgumentError, """
    Unsupported agency: #{inspect(agency)}

    Supported agencies: :hse, :ea, :environment_agency (alias for :ea), :sepa

    To add support for a new agency, create a module implementing the
    EhsEnforcement.Scraping.AgencyBehavior and add it to get_agency_module/1.
    """
  end

  @doc """
  Check if scraping is enabled for the given agency and scrape type.

  This is a convenience function that can be used by agency implementations
  to check if scraping is enabled before proceeding.

  ## Parameters

  - `agency` - Agency atom (:hse, :ea, etc.)
  - `scrape_type` - Type of scraping (:manual, :scheduled)
  - `config` - Scraping configuration

  ## Returns

  - `true` if scraping is enabled
  - `false` if scraping is disabled

  ## Example

      iex> scraping_enabled?(:hse, :manual, config)
      true

      iex> scraping_enabled?(:ea, :scheduled, config)
      false
  """
  def scraping_enabled?(_agency, scrape_type, config) do
    case scrape_type do
      :manual -> Map.get(config, :manual_scraping_enabled, true)
      :scheduled -> Map.get(config, :scheduled_scraping_enabled, false)
      _ -> false
    end
  end

  @doc """
  Generate a unique session ID for scraping sessions.

  This is a convenience function for agency implementations to generate
  consistent session IDs.

  ## Returns

  - String session ID (16 characters, lowercase hex)

  ## Example

      iex> generate_session_id()
      "a1b2c3d4e5f67890"
  """
  def generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
