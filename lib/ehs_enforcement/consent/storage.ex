defmodule EhsEnforcement.Consent.Storage do
  @moduledoc """
  Custom storage module for cookie consent that syncs to database for authenticated users.

  This extends the base AshCookieConsent.Storage with database persistence for logged-in users.

  ## Behavior

  - **Anonymous users**: Consent stored in cookies only (via base Storage module)
  - **Authenticated users**: Consent stored in cookies AND database
  - **Returning authenticated users**: Consent loaded from database (if newer than cookie)

  ## Usage

  Configure in your Plug:

      plug AshCookieConsent.Plug,
        storage: EhsEnforcement.Consent.Storage,
        user_id_key: :current_user,
        skip_session_cache: true
  """

  alias AshCookieConsent.Storage, as: BaseStorage
  alias EhsEnforcement.Consent.ConsentSettings
  require Ash.Query

  @doc """
  Gets consent from storage, checking database for authenticated users.

  Priority order:
  1. Connection assigns (already loaded this request)
  2. Session (cached from previous request)
  3. Cookie (browser storage)
  4. Database (for authenticated users only)
  """
  def get_consent(conn, opts \\ []) do
    # Try base storage first (assigns -> session -> cookie)
    case BaseStorage.get_consent(conn, opts) do
      nil ->
        # No consent in cookie/session, check database for authenticated users
        load_from_database(conn, opts)

      consent ->
        # Consent found in cookie/session
        # For authenticated users, check if DB version is newer
        case load_from_database(conn, opts) do
          nil ->
            consent

          db_consent ->
            # Return whichever is newer
            if newer?(db_consent, consent), do: db_consent, else: consent
        end
    end
  end

  @doc """
  Saves consent to storage, including database for authenticated users.

  For anonymous users: Saves to cookie only (via base Storage)
  For authenticated users: Saves to cookie AND database
  """
  def put_consent(conn, consent, opts \\ []) do
    # Always save to base storage (cookie + optionally session)
    conn = BaseStorage.put_consent(conn, consent, opts)

    # Additionally save to database if user is authenticated
    if user = get_user(conn, opts) do
      save_to_database(user, consent, opts)
    end

    conn
  end

  @doc """
  Deletes consent from all storage tiers.
  """
  def delete_consent(conn, opts \\ []) do
    # Delete from base storage (cookie/session)
    conn = BaseStorage.delete_consent(conn, opts)

    # Also delete from database if user is authenticated
    if user = get_user(conn, opts) do
      delete_from_database(user, opts)
    end

    conn
  end

  # Private functions

  defp get_user(conn, opts) do
    user_id_key = Keyword.get(opts, :user_id_key, :current_user)

    case Map.get(conn.assigns, user_id_key) do
      nil -> nil
      user when is_struct(user) -> user
      _other -> nil
    end
  end

  defp load_from_database(conn, opts) do
    case get_user(conn, opts) do
      nil ->
        nil

      user ->
        # Query for the most recent consent for this user
        ConsentSettings
        |> Ash.Query.filter(user_id == ^user.id)
        |> Ash.Query.sort(consented_at: :desc)
        |> Ash.Query.limit(1)
        |> Ash.read()
        |> case do
          {:ok, [consent_record]} ->
            # Convert to consent map format
            %{
              "terms" => consent_record.terms,
              "groups" => consent_record.groups,
              "consented_at" => consent_record.consented_at,
              "expires_at" => consent_record.expires_at
            }

          {:ok, []} ->
            nil

          {:error, _error} ->
            nil
        end
    end
  end

  defp save_to_database(user, consent, _opts) do
    # Create consent record with user_id
    consent_params = %{
      user_id: user.id,
      terms: get_field(consent, "terms"),
      groups: get_field(consent, "groups"),
      consented_at: get_field(consent, "consented_at"),
      expires_at: get_field(consent, "expires_at")
    }

    # Use grant_consent action which auto-sets timestamps if not provided
    ConsentSettings
    |> Ash.Changeset.for_create(:create, consent_params)
    |> Ash.create()
    |> case do
      {:ok, _record} -> :ok
      {:error, _error} -> :error
    end
  end

  defp delete_from_database(user, _opts) do
    # Delete all consent records for this user
    ConsentSettings
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read!()
    |> Enum.each(fn record ->
      Ash.destroy(record)
    end)

    :ok
  end

  # Helper to check if consent1 is newer than consent2
  defp newer?(consent1, consent2) do
    time1 = get_timestamp(consent1, "consented_at")
    time2 = get_timestamp(consent2, "consented_at")

    cond do
      is_nil(time1) -> false
      is_nil(time2) -> true
      true -> DateTime.compare(time1, time2) == :gt
    end
  end

  defp get_timestamp(consent, field) do
    case get_field(consent, field) do
      %DateTime{} = dt -> dt
      timestamp when is_binary(timestamp) -> parse_datetime(timestamp)
      _ -> nil
    end
  end

  defp parse_datetime(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  # Security: Only convert known field names to atoms
  # Field names are hardcoded in this module ("terms", "groups", "consented_at", "expires_at")
  defp get_field(consent, field) when is_map(consent) and is_binary(field) do
    Map.get(consent, field) || Map.get(consent, String.to_existing_atom(field))
  end

  defp get_field(consent, field) when is_map(consent) do
    Map.get(consent, field)
  end

  defp get_field(_, _), do: nil
end
