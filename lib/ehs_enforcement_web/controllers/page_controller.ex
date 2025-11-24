defmodule EhsEnforcementWeb.PageController do
  use EhsEnforcementWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def redirect_to_cases(conn, _params) do
    # Updated: /cases route removed during Svelte migration
    # Redirect to home page instead
    redirect(conn, to: ~p"/")
  end
end
