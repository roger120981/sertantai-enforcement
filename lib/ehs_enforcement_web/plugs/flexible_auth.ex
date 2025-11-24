defmodule EhsEnforcementWeb.Plugs.FlexibleAuth do
  @moduledoc """
  Flexible authentication plug that supports both JWT and session-based authentication.

  This plug tries JWT authentication first (for tenant users from sertantai-auth),
  and falls back to session-based authentication (for admin users via GitHub OAuth).

  ## Authentication Methods (in order of precedence)

  1. **JWT Token** (Bearer Authorization header)
     - Used by tenant users from sertantai-auth
     - Sets `:current_jwt_user_id`, `:current_org_id`, `:current_role`

  2. **Session Cookie** (Phoenix session)
     - Used by admin users via GitHub OAuth
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
  - `:current_user` - Full Ash user struct (session auth)
  - `:current_jwt_user_id`, `:current_org_id`, `:current_role` (JWT auth)
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

  # Try JWT authentication using the existing JwtAuth plug
  defp try_jwt_auth(conn) do
    # Use the existing JWT auth plug
    case EhsEnforcementWeb.Plugs.JwtAuth.call(conn, []) do
      %{halted: true} ->
        # JWT auth failed, try session auth as fallback
        Logger.debug("JWT auth failed, trying session auth fallback")
        try_session_auth(conn)

      success_conn ->
        # JWT auth succeeded
        success_conn
    end
  rescue
    e ->
      Logger.warning("JWT auth error: #{inspect(e)}, trying session auth fallback")
      try_session_auth(conn)
  end

  # Try session-based authentication (GitHub OAuth)
  defp try_session_auth(conn) do
    # Load user from session using AshAuthentication
    conn = AshAuthentication.Plug.Helpers.retrieve_from_session(conn, :ehs_enforcement)

    case conn.assigns[:current_user] do
      nil ->
        # No session auth either, return unauthorized
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Not authenticated"})
        |> halt()

      _user ->
        # Session auth succeeded
        Logger.debug(
          "Session auth succeeded for user: #{inspect(conn.assigns[:current_user].email)}"
        )

        conn
    end
  end
end
