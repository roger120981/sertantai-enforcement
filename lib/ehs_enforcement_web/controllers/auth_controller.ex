defmodule EhsEnforcementWeb.AuthController do
  @moduledoc """
  Handles Ash Authentication callbacks and user session management.
  """

  use EhsEnforcementWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, _activity, user, token) do
    require Logger
    Logger.debug("Auth success - token: #{inspect(token)}")

    token_type = if is_nil(token), do: nil, else: Map.get(token, :__struct__, :not_a_struct)
    Logger.debug("Auth success - token type: #{inspect(token_type)}")

    # Load the display_name calculation safely
    user_with_display_name = Ash.load!(user, [:display_name])

    display_name =
      Map.get(user_with_display_name, :display_name) || user.name || user.github_login ||
        user.email

    # Extract token string from token struct
    token_string = extract_token_string(token)
    Logger.debug("Auth success - extracted token_string: #{inspect(token_string)}")

    # Get frontend URL from config (defaults to localhost:5173 for dev)
    frontend_url = Application.get_env(:ehs_enforcement, :frontend_url, "http://localhost:5173")

    cond do
      # JWT token available: tenant users from sertantai-auth → redirect to frontend
      token_string && frontend_url ->
        conn
        |> store_in_session(user)
        |> redirect(external: "#{frontend_url}/auth/callback?token=#{token_string}")

      # No JWT token: admin GitHub OAuth users → stay in backend LiveView app
      true ->
        conn
        |> store_in_session(user)
        |> assign(:current_user, user)
        |> put_flash(:info, "Welcome #{display_name}!")
        |> redirect(to: "/")
    end
  end

  # Extract token string from Ash token struct
  defp extract_token_string(token) when is_binary(token), do: token
  defp extract_token_string(%{token: token}) when is_binary(token), do: token
  defp extract_token_string(%{jti: jti}) when is_binary(jti), do: jti
  defp extract_token_string(_), do: nil

  def failure(conn, _activity, reason) do
    # Safely convert error to string
    error_message =
      case reason do
        %{message: msg} when is_binary(msg) -> msg
        error when is_binary(error) -> error
        error -> inspect(error)
      end

    conn
    |> put_flash(:error, "Authentication failed: #{error_message}")
    |> redirect(to: "/")
  end

  def sign_out(conn, _params) do
    # Clear session with error handling for token revocation failures
    conn =
      try do
        clear_session(conn, :ehs_enforcement)
      rescue
        error ->
          # Log the error but still allow logout to succeed
          require Logger
          Logger.error("Error during token revocation on logout: #{inspect(error)}")

          # Fallback to basic session clearing
          Plug.Conn.clear_session(conn)
      end

    conn
    |> put_flash(:info, "Successfully signed out")
    |> redirect(to: "/")
  end
end
