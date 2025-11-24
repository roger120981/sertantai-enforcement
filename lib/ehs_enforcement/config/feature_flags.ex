defmodule EhsEnforcement.Config.FeatureFlags do
  @moduledoc """
  Dynamic feature flag system for the EHS Enforcement application.

  Supports environment variable configuration, test overrides,
  and provides comprehensive feature flag management.
  """

  use GenServer

  # Simple ETS table for test overrides when GenServer isn't running
  @test_overrides_table :feature_flags_test_overrides

  # Client API

  @doc """
  Checks if a feature flag is enabled.
  """
  def enabled?(flag_name) do
    case GenServer.whereis(__MODULE__) do
      nil ->
        # Fallback for when GenServer isn't started (during tests)
        get_flag_value_direct(flag_name)

      _pid ->
        GenServer.call(__MODULE__, {:enabled?, flag_name})
    end
  end

  @doc """
  Returns all feature flags with their current status.
  """
  def all_flags do
    case GenServer.whereis(__MODULE__) do
      nil ->
        # Fallback for when GenServer isn't started (during tests)
        %{
          auto_sync: get_flag_value_direct(:auto_sync),
          manual_sync: get_flag_value_direct(:manual_sync),
          export_enabled: get_flag_value_direct(:export_enabled)
        }

      _pid ->
        GenServer.call(__MODULE__, :all_flags)
    end
  end

  @doc """
  Temporarily enables a feature for testing.
  """
  def enable_for_test(flag_name) do
    case GenServer.whereis(__MODULE__) do
      nil ->
        _ = ensure_test_table_exists()
        true = :ets.insert(@test_overrides_table, {flag_name, true})
        :ok

      _pid ->
        GenServer.call(__MODULE__, {:enable_for_test, flag_name})
    end
  end

  @doc """
  Temporarily disables a feature for testing.
  """
  def disable_for_test(flag_name) do
    case GenServer.whereis(__MODULE__) do
      nil ->
        _ = ensure_test_table_exists()
        true = :ets.insert(@test_overrides_table, {flag_name, false})
        :ok

      _pid ->
        GenServer.call(__MODULE__, {:disable_for_test, flag_name})
    end
  end

  @doc """
  Resets all test overrides to environment/default values.
  """
  def reset_test_overrides do
    case GenServer.whereis(__MODULE__) do
      nil ->
        _ = ensure_test_table_exists()
        true = :ets.delete_all_objects(@test_overrides_table)
        :ok

      _pid ->
        GenServer.call(__MODULE__, :reset_test_overrides)
    end
  end

  @doc """
  Returns the source of a feature flag's value.
  """
  def get_flag_source(flag_name) do
    case GenServer.whereis(__MODULE__) do
      nil -> determine_flag_source_direct(flag_name)
      _pid -> GenServer.call(__MODULE__, {:get_flag_source, flag_name})
    end
  end

  # Security: Whitelist allowed feature flags to prevent DOS via String.to_atom
  @allowed_flags ~w(auto_sync manual_sync export_enabled)

  @doc """
  Validates a feature flag name.
  """
  def validate_flag_name(flag_name) when is_atom(flag_name) do
    known_flags = [:auto_sync, :manual_sync, :export_enabled]

    if flag_name in known_flags do
      :ok
    else
      {:error, :unknown_flag}
    end
  end

  def validate_flag_name(flag_name) when is_binary(flag_name) do
    # Security: Validate flag name against whitelist before converting to atom
    if flag_name in @allowed_flags do
      validate_flag_name(String.to_existing_atom(flag_name))
    else
      {:error, :unknown_flag}
    end
  end

  @doc """
  Returns human-readable descriptions for all flags.
  """
  def flag_descriptions do
    %{
      auto_sync:
        "Automatically sync data from agencies. Configure with AUTO_SYNC_ENABLED environment variable.",
      manual_sync: "Allow manual sync operations. This feature is permanently enabled.",
      export_enabled: "Enable data export functionality. This feature is permanently enabled."
    }
  end

  @doc """
  Returns the environment variable name for configurable flags.
  """
  def environment_variable_for(:auto_sync), do: "AUTO_SYNC_ENABLED"
  def environment_variable_for(_), do: nil

  @doc """
  Returns a comprehensive status summary for all flags.
  """
  def flag_status_summary do
    flags = all_flags()
    enabled_count = Enum.count(flags, fn {_flag, enabled} -> enabled end)
    disabled_count = map_size(flags) - enabled_count

    %{
      enabled_count: enabled_count,
      disabled_count: disabled_count,
      flags: flags
    }
  end

  # GenServer implementation

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{test_overrides: %{}}}
  end

  @impl true
  def handle_call({:enabled?, flag_name}, _from, state) do
    enabled = get_flag_value(flag_name, state.test_overrides)
    {:reply, enabled, state}
  end

  @impl true
  def handle_call(:all_flags, _from, state) do
    flags = %{
      auto_sync: get_flag_value(:auto_sync, state.test_overrides),
      manual_sync: get_flag_value(:manual_sync, state.test_overrides),
      export_enabled: get_flag_value(:export_enabled, state.test_overrides)
    }

    {:reply, flags, state}
  end

  @impl true
  def handle_call({:enable_for_test, flag_name}, _from, state) do
    new_overrides = Map.put(state.test_overrides, flag_name, true)
    {:reply, :ok, %{state | test_overrides: new_overrides}}
  end

  @impl true
  def handle_call({:disable_for_test, flag_name}, _from, state) do
    new_overrides = Map.put(state.test_overrides, flag_name, false)
    {:reply, :ok, %{state | test_overrides: new_overrides}}
  end

  @impl true
  def handle_call(:reset_test_overrides, _from, state) do
    {:reply, :ok, %{state | test_overrides: %{}}}
  end

  @impl true
  def handle_call({:get_flag_source, flag_name}, _from, state) do
    source = determine_flag_source(flag_name, state.test_overrides)
    {:reply, source, state}
  end

  # Direct access functions for when GenServer isn't started

  defp get_flag_value_direct(flag_name) do
    test_overrides = get_test_overrides_from_ets()
    get_flag_value(flag_name, test_overrides)
  end

  defp determine_flag_source_direct(flag_name) do
    test_overrides = get_test_overrides_from_ets()
    determine_flag_source(flag_name, test_overrides)
  end

  defp get_test_overrides_from_ets do
    case :ets.whereis(@test_overrides_table) do
      :undefined ->
        %{}

      _tid ->
        @test_overrides_table
        |> :ets.tab2list()
        |> Map.new()
    end
  end

  defp ensure_test_table_exists do
    case :ets.whereis(@test_overrides_table) do
      :undefined ->
        :ets.new(@test_overrides_table, [:named_table, :public, :set])

      _tid ->
        :ok
    end
  end

  # Private functions

  defp get_flag_value(flag_name, test_overrides) do
    cond do
      Map.has_key?(test_overrides, flag_name) ->
        Map.get(test_overrides, flag_name)

      flag_name == :auto_sync ->
        parse_boolean(System.get_env("AUTO_SYNC_ENABLED", "false"))

      flag_name == :manual_sync ->
        # Permanently enabled
        true

      flag_name == :export_enabled ->
        # Permanently enabled
        true

      true ->
        # Unknown flags default to false
        false
    end
  end

  defp determine_flag_source(flag_name, test_overrides) do
    cond do
      Map.has_key?(test_overrides, flag_name) ->
        :test_override

      flag_name in [:manual_sync, :export_enabled] ->
        :permanent

      flag_name == :auto_sync and System.get_env("AUTO_SYNC_ENABLED") ->
        :environment

      flag_name == :auto_sync ->
        :default

      true ->
        :unknown
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

  # Fallback functions for when GenServer isn't started (during testing)
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
end
