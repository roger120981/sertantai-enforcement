defmodule EhsEnforcementWeb.Api.CurrentUserController do
  @moduledoc """
  API endpoint for retrieving current user information based on JWT token.
  Used by the frontend after OAuth redirect.
  """

  use EhsEnforcementWeb, :controller
  require Ash.Query

  def show(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      user ->
        # Load any calculated fields needed
        user_with_details = Ash.load!(user, [:display_name])

        conn
        |> json(%{
          id: user.id,
          email: user.email,
          name: user.name,
          github_login: user.github_login,
          avatar_url: user.avatar_url,
          is_admin: user.is_admin,
          display_name: Map.get(user_with_details, :display_name)
        })
    end
  end
end
