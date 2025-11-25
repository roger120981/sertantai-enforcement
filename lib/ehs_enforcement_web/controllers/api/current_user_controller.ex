defmodule EhsEnforcementWeb.Api.CurrentUserController do
  @moduledoc """
  API endpoint for retrieving current user information based on JWT token.
  Used by the frontend after OAuth redirect.
  """

  use EhsEnforcementWeb, :controller
  require Ash.Query

  def show(conn, _params) do
    require Logger

    case conn.assigns[:current_user] do
      nil ->
        Logger.warning("CurrentUserController: no current_user in assigns")

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      user ->
        # Load any calculated fields needed
        user_with_details = Ash.load!(user, [:display_name])

        response_data = %{
          id: user.id,
          email: to_string(user.email),
          name: user.name,
          github_login: user.github_login,
          avatar_url: user.avatar_url,
          is_admin: user.is_admin,
          display_name: Map.get(user_with_details, :display_name)
        }

        conn
        |> json(response_data)
    end
  end
end
