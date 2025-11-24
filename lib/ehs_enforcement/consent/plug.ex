defmodule EhsEnforcement.Consent.Plug do
  @moduledoc """
  Custom consent plug with database sync for authenticated users.

  This extends AshCookieConsent.Plug to add database persistence for logged-in users.

  ## Usage

  In your router:

      pipeline :browser do
        # ... other plugs
        plug EhsEnforcement.Consent.Plug,
          resource: EhsEnforcement.Consent.ConsentSettings,
          user_id_key: :current_user,
          skip_session_cache: true
      end
  """

  import Plug.Conn
  alias EhsEnforcement.Consent.Storage

  @behaviour Plug

  @impl true
  def init(opts) do
    # Delegate to base plug for configuration
    AshCookieConsent.Plug.init(opts)
  end

  @impl true
  def call(conn, config) do
    # Build options for storage operations
    storage_opts = [
      resource: config.resource,
      cookie_name: config.cookie_name,
      session_key: config.session_key,
      user_id_key: config.user_id_key
    ]

    # Use custom storage that includes database sync
    consent = Storage.get_consent(conn, storage_opts)

    # Determine if consent modal should be shown
    show_modal = should_show_modal?(consent)

    # Set assigns (same as base plug)
    conn
    |> assign(:consent, consent)
    |> assign(:show_consent_modal, show_modal)
    |> assign(:cookie_groups, AshCookieConsent.cookie_groups())
  end

  # Private functions

  defp should_show_modal?(nil), do: true

  defp should_show_modal?(consent) when is_map(consent) do
    # Check if consent has groups
    groups = get_field(consent, "groups")

    cond do
      # No groups or empty groups - need consent
      is_nil(groups) -> true
      groups == [] -> true
      # Has groups but expired - need new consent
      consent_expired?(consent) -> true
      # Has valid groups and not expired - don't need consent
      true -> false
    end
  end

  defp should_show_modal?(_), do: true

  # Check if consent has expired (handles both string and atom keys)
  defp consent_expired?(consent) do
    expires_at = get_field(consent, "expires_at")

    case expires_at do
      nil ->
        false

      %DateTime{} = dt ->
        DateTime.compare(DateTime.utc_now(), dt) == :gt

      timestamp when is_binary(timestamp) ->
        case parse_datetime(timestamp) do
          nil -> false
          dt -> DateTime.compare(DateTime.utc_now(), dt) == :gt
        end

      _ ->
        false
    end
  end

  defp parse_datetime(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  # Security: Only convert known field names to atoms
  # Field names are hardcoded in this module ("groups", "expires_at")
  defp get_field(consent, field) when is_map(consent) and is_binary(field) do
    Map.get(consent, field) || Map.get(consent, String.to_existing_atom(field))
  end

  defp get_field(consent, field) when is_map(consent) do
    Map.get(consent, field)
  end
end
