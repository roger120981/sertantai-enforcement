defmodule EhsEnforcement.Config.Settings do
  @moduledoc """
  Central configuration management for the EHS Enforcement application.

  Handles loading and accessing configuration from environment variables
  with proper defaults and validation.
  """

  @doc """
  Returns Airtable configuration with environment variable overrides.
  """
  def get_airtable_config do
    %{
      api_key: System.get_env("AT_UK_E_API_KEY"),
      base_id: System.get_env("AIRTABLE_BASE_ID", "appq5OQW9bTHC1zO5"),
      sync_interval_minutes: parse_sync_interval(System.get_env("SYNC_INTERVAL", "60"))
    }
  end

  @doc """
  Returns configuration for a specific agency.
  """
  def get_agency_config(:hse) do
    %{
      enabled: parse_boolean(System.get_env("HSE_ENABLED", "true")),
      base_url: "https://resources.hse.gov.uk",
      tables: %{
        cases: "tbl6NZm9bLU2ijivf",
        notices: "tbl6NZm9bLU2ijivf"
      }
    }
  end

  def get_agency_config(_unknown_agency), do: nil

  @doc """
  Returns feature flag configuration.
  """
  def get_feature_flags do
    %{
      auto_sync: parse_boolean(System.get_env("AUTO_SYNC_ENABLED", "false")),
      manual_sync: true,
      export_enabled: true
    }
  end

  @doc """
  Validates the entire configuration.
  """
  def validate_configuration do
    # Check required vars first, then specific validations
    case validate_required_env_vars() do
      :ok ->
        # Only validate specifics if required vars are present
        with :ok <- validate_airtable_config(),
             :ok <- validate_sync_interval() do
          :ok
        else
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a feature is enabled.
  """
  def feature_enabled?(feature_name) do
    flags = get_feature_flags()
    Map.get(flags, feature_name, false)
  end

  @doc """
  Returns list of all enabled agencies.
  """
  def get_all_agencies do
    [:hse]
    |> Enum.filter(fn agency ->
      config = get_agency_config(agency)
      config && config[:enabled]
    end)
  end

  @doc """
  Returns database configuration.
  """
  def get_database_config do
    %{
      url: System.get_env("DATABASE_URL"),
      pool_size: parse_integer(System.get_env("DATABASE_POOL_SIZE", "10"))
    }
  end

  # Private functions

  defp parse_sync_interval(value) when is_binary(value) do
    case Integer.parse(value) do
      {interval, ""} when interval > 0 -> interval
      # Default fallback
      _ -> 60
    end
  end

  defp parse_boolean("true"), do: true
  defp parse_boolean("TRUE"), do: true
  defp parse_boolean("True"), do: true
  defp parse_boolean("1"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean("FALSE"), do: false
  defp parse_boolean("False"), do: false
  defp parse_boolean("0"), do: false
  defp parse_boolean(_), do: false

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      # Default fallback
      _ -> 10
    end
  end

  defp validate_required_env_vars do
    required_vars = ["AT_UK_E_API_KEY", "DATABASE_URL"]

    missing =
      Enum.filter(required_vars, fn var ->
        System.get_env(var) in [nil, ""]
      end)

    case missing do
      [] ->
        :ok

      ["AT_UK_E_API_KEY" | _] ->
        {:error, :missing_airtable_api_key}

      ["DATABASE_URL" | _] ->
        {:error, :missing_database_url}

      # Security: Avoid dynamic atom creation - this case should never happen
      # since required_vars only contains the two vars handled above
      [var | _] ->
        {:error, {:missing_env_var, var}}
    end
  end

  defp validate_airtable_config do
    api_key = System.get_env("AT_UK_E_API_KEY")

    # API key presence already checked in validate_required_env_vars
    if api_key && String.length(api_key) < 10 do
      {:error, :invalid_api_key_format}
    else
      :ok
    end
  end

  defp validate_sync_interval do
    interval_str = System.get_env("SYNC_INTERVAL", "60")

    case Integer.parse(interval_str) do
      {interval, ""} when interval > 0 -> :ok
      _ -> {:error, :invalid_sync_interval}
    end
  end
end
