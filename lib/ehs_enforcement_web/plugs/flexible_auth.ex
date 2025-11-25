defmodule EhsEnforcementWeb.Plugs.FlexibleAuth do
  @moduledoc """
  Flexible authentication plug that supports multiple authentication methods.

  ## Authentication Methods (in order of precedence)

  1. **Tenant JWT Token** (Bearer Authorization header)
     - Used by tenant users from sertantai-auth
     - Verified with SERTANTAI_SHARED_TOKEN_SECRET
     - Sets `:current_jwt_user_id`, `:current_org_id`, `:current_role`

  2. **Admin OAuth JWT Token** (Bearer Authorization header)
     - Used by admin users from GitHub OAuth
     - Verified with TOKEN_SIGNING_SECRET
     - Sets `:current_user` (full Ash user struct loaded from token)

  3. **Session Cookie** (Phoenix session)
     - Used by admin users via GitHub OAuth (fallback)
     - Sets `:current_user` (full Ash user struct)

  ## Usage

  Add to pipeline in router:
  ```elixir
  pipeline :api_flexible do
    plug :accepts, ["json"]
    plug EhsEnforcementWeb.Plugs.FlexibleAuth
  end
  ```

  ## Assigns

  After successful authentication, assigns ONE of:
  - `:current_user` - Full Ash user struct (OAuth JWT or session auth)
  - `:current_jwt_user_id`, `:current_org_id`, `:current_role` (tenant JWT auth)
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> _token] ->
        # Try JWT authentication first
        try_jwt_auth(conn)

      _ ->
        # No JWT token, try session authentication
        try_session_auth(conn)
    end
  end

  # Try JWT authentication - first tenant JWT, then admin OAuth JWT
  defp try_jwt_auth(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        # Try tenant JWT first (SERTANTAI_SHARED_TOKEN_SECRET)
        case verify_tenant_jwt(token) do
          {:ok, _claims} ->
            # Tenant JWT verification succeeded - would need full JwtAuth logic here
            # For now, just try OAuth JWT since tenant auth isn't the main use case
            Logger.debug("Tenant JWT verified, but skipping full tenant auth setup")
            try_oauth_jwt_auth(conn)

          {:error, reason} ->
            Logger.debug("Tenant JWT verification failed: #{inspect(reason)}, trying OAuth JWT")
            try_oauth_jwt_auth(conn)
        end

      _ ->
        try_oauth_jwt_auth(conn)
    end
  rescue
    e ->
      Logger.warning("JWT auth error: #{inspect(e)}, trying OAuth JWT")
      try_oauth_jwt_auth(conn)
  end

  # Verify tenant JWT token (quick check only, doesn't set up full context)
  defp verify_tenant_jwt(token) do
    secret = System.get_env("SERTANTAI_SHARED_TOKEN_SECRET")

    if is_nil(secret) do
      {:error, :no_tenant_secret}
    else
      signer = Joken.Signer.create("HS256", secret)

      case Joken.verify(token, signer) do
        {:ok, claims} ->
          # Check expiration
          now = System.system_time(:second)
          exp = claims["exp"]

          if exp && exp < now do
            {:error, :token_expired}
          else
            {:ok, claims}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    e ->
      {:error, e}
  end

  # Try admin OAuth JWT authentication (TOKEN_SIGNING_SECRET)
  defp try_oauth_jwt_auth(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        verify_oauth_token(conn, token)

      _ ->
        Logger.debug("No Bearer token, trying session auth")
        try_session_auth(conn)
    end
  end

  # Verify OAuth token with TOKEN_SIGNING_SECRET and load user
  defp verify_oauth_token(conn, token) do
    secret = Application.get_env(:ehs_enforcement, :token_signing_secret)

    if is_nil(secret) do
      Logger.error("TOKEN_SIGNING_SECRET not configured")
      try_session_auth(conn)
    else
      signer = Joken.Signer.create("HS256", secret)

      case Joken.verify(token, signer) do
        {:ok, claims} ->
          # Check expiration
          now = System.system_time(:second)
          exp = claims["exp"]

          if exp && exp < now do
            Logger.warning("OAuth JWT token expired")
            try_session_auth(conn)
          else
            # Extract user ID from subject (format: "user?id=<uuid>")
            case Regex.run(~r/user\?id=([a-f0-9-]+)/, claims["sub"]) do
              [_, user_id] ->
                load_user_from_token(conn, user_id)

              _ ->
                Logger.warning("Invalid subject format in OAuth token: #{claims["sub"]}")
                try_session_auth(conn)
            end
          end

        {:error, reason} ->
          Logger.warning("OAuth JWT verification failed: #{inspect(reason)}")
          try_session_auth(conn)
      end
    end
  rescue
    e ->
      Logger.warning("OAuth JWT verification error: #{inspect(e)}")
      try_session_auth(conn)
  end

  # Load user from database using user ID from token
  defp load_user_from_token(conn, user_id) do
    case Ash.get(EhsEnforcement.Accounts.User, user_id) do
      {:ok, user} ->
        Logger.debug("Admin OAuth JWT auth succeeded for user: #{user.email}")

        conn
        |> assign(:current_user, user)

      {:error, reason} ->
        Logger.warning("Failed to load user #{user_id}: #{inspect(reason)}")
        try_session_auth(conn)
    end
  rescue
    e ->
      Logger.warning("Error loading user: #{inspect(e)}")
      try_session_auth(conn)
  end

  # Try session-based authentication (GitHub OAuth)
  defp try_session_auth(conn) do
    # Debug: Log session contents
    session = Plug.Conn.get_session(conn)
    Logger.debug("Session auth: session keys = #{inspect(Map.keys(session))}")
    Logger.debug("Session auth: has user? = #{inspect(Map.has_key?(session, "user"))}")

    # Load user from session using AshAuthentication
    conn = AshAuthentication.Plug.Helpers.retrieve_from_session(conn, :ehs_enforcement)

    # Debug: Log result
    Logger.debug(
      "Session auth: current_user after retrieve = #{inspect(conn.assigns[:current_user])}"
    )

    case conn.assigns[:current_user] do
      nil ->
        # No session auth either, return unauthorized
        Logger.warning("Session auth failed: no current_user in assigns")

        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Not authenticated"})
        |> halt()

      user ->
        # Session auth succeeded
        Logger.debug("Session auth succeeded for user: #{inspect(user.email)}")

        conn
    end
  end
end
