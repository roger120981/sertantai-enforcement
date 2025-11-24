defmodule EhsEnforcementWeb.Plugs.JwtAuth do
  @moduledoc """
  Plug to verify JWT tokens from sertantai-auth and set up request context.

  Uses Joken to verify JWT signature with SERTANTAI_SHARED_TOKEN_SECRET.
  Extracts user_id from 'sub' claim, org_id and role from custom claims.
  Sets up tenant context for Row-Level Security (RLS).

  ## Usage

  Add to pipeline in router:
  ```elixir
  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug EhsEnforcementWeb.Plugs.JwtAuth
  end
  ```

  ## Assigns

  On successful verification, assigns the following to conn:
  - `:current_jwt_user_id` - The user's UUID from JWT
  - `:current_org_id` - The user's organization UUID
  - `:current_role` - The user's role atom (:owner, :admin, :member, :viewer)

  ## Token Format

  Expected JWT claims:
  - `sub`: "user?id=<uuid>" (AshAuthentication format)
  - `org_id`: "<uuid>" (organization identifier)
  - `role`: "owner" | "admin" | "member" | "viewer"

  ## Security Notes

  - JWT verification uses SERTANTAI_SHARED_TOKEN_SECRET (must match sertantai-auth)
  - Sets RLS context via set_current_org_id() PostgreSQL function
  - Does NOT load user record (EHS Enforcement has no user table in main DB)
  - Use GitHub OAuth for admin authentication (separate concern)
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        verify_token_and_set_context(conn, token)

      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Missing or invalid authorization header"})
        |> halt()
    end
  end

  defp verify_token_and_set_context(conn, token) do
    secret = System.get_env("SERTANTAI_SHARED_TOKEN_SECRET")

    if is_nil(secret) do
      Logger.error("SERTANTAI_SHARED_TOKEN_SECRET is not configured")

      conn
      |> put_status(:internal_server_error)
      |> Phoenix.Controller.json(%{error: "Authentication not configured"})
      |> halt()
    else
      signer = Joken.Signer.create("HS256", secret)

      # Verify token signature first
      case Joken.verify(token, signer) do
        {:ok, claims} ->
          # Check expiration manually
          now = System.system_time(:second)
          exp = claims["exp"]

          if exp && exp < now do
            Logger.warning("JWT token expired")

            conn
            |> put_status(:unauthorized)
            |> Phoenix.Controller.json(%{error: "Token expired"})
            |> halt()
          else
            verify_claims_and_set_context(conn, claims)
          end

        {:error, reason} ->
          Logger.warning("JWT verification failed: #{inspect(reason)}")

          conn
          |> put_status(:unauthorized)
          |> Phoenix.Controller.json(%{error: "Invalid or expired token"})
          |> halt()
      end
    end
  end

  defp verify_claims_and_set_context(conn, claims) do
    with {:ok, user_id} <- extract_user_id(claims["sub"]),
         {:ok, org_id} <- extract_org_id(claims["org_id"]),
         {:ok, role} <- extract_role(claims["role"]),
         :ok <- set_tenant_context(org_id) do
      Logger.debug("JWT verified - User: #{user_id}, Org: #{org_id}, Role: #{inspect(role)}")

      conn
      |> assign(:current_jwt_user_id, user_id)
      |> assign(:current_org_id, org_id)
      |> assign(:current_role, role)
    else
      {:error, reason} ->
        Logger.warning("Token verification failed: #{inspect(reason)}")

        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Invalid token: #{reason}"})
        |> halt()
    end
  end

  # Extract user ID from AshAuthentication 'sub' claim
  # Format: "user?id=<uuid>"
  defp extract_user_id("user?id=" <> user_id) when is_binary(user_id) do
    {:ok, user_id}
  end

  defp extract_user_id(sub) do
    Logger.warning("Invalid sub claim format: #{inspect(sub)}")
    {:error, "invalid_user_id"}
  end

  # Extract organization ID from custom 'org_id' claim
  defp extract_org_id(org_id) when is_binary(org_id) do
    {:ok, org_id}
  end

  defp extract_org_id(nil) do
    Logger.warning("Missing org_id claim in token")
    {:error, "missing_org_id"}
  end

  defp extract_org_id(org_id) do
    Logger.warning("Invalid org_id claim format: #{inspect(org_id)}")
    {:error, "invalid_org_id"}
  end

  # Extract role from custom 'role' claim
  # Convert string to atom
  defp extract_role(role) when is_binary(role) do
    role_atom =
      case role do
        "owner" -> :owner
        "admin" -> :admin
        "member" -> :member
        "viewer" -> :viewer
        other -> String.to_existing_atom(other)
      end

    {:ok, role_atom}
  rescue
    ArgumentError ->
      Logger.warning("Invalid role: #{inspect(role)}")
      {:error, "invalid_role"}
  end

  defp extract_role(nil) do
    Logger.warning("Missing role claim in token")
    {:error, "missing_role"}
  end

  defp extract_role(role) do
    Logger.warning("Invalid role claim format: #{inspect(role)}")
    {:error, "invalid_role"}
  end

  # Set tenant context in database session for RLS policies
  # This calls the set_current_org_id() PostgreSQL function
  # Note: org_id is guaranteed to be a binary string by extract_org_id/1
  defp set_tenant_context(org_id) when is_binary(org_id) do
    # Convert UUID string to Ecto.UUID type for PostgreSQL
    with {:ok, uuid_binary} <- Ecto.UUID.dump(org_id),
         query = "SELECT set_current_org_id($1::uuid)",
         {:ok, _result} <- Ecto.Adapters.SQL.query(EhsEnforcement.Repo, query, [uuid_binary]) do
      Logger.debug("Tenant context set: #{org_id}")
      :ok
    else
      :error ->
        Logger.error("Invalid UUID format: #{org_id}")
        {:error, "invalid_uuid_format"}

      {:error, error} ->
        Logger.error("Failed to set tenant context: #{inspect(error)}")
        {:error, "failed_to_set_tenant_context"}
    end
  end
end
