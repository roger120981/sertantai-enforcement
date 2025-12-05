defmodule EhsEnforcementWeb.Router do
  use EhsEnforcementWeb, :router
  use AshAuthentication.Phoenix.Router

  import EhsEnforcementWeb.Plugs.AuthHelpers, only: [load_current_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_cookies
    plug :fetch_live_flash
    plug :put_root_layout, html: {EhsEnforcementWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; " <>
          "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
          "style-src 'self' 'unsafe-inline'; " <>
          "img-src 'self' data: https:; " <>
          "font-src 'self' data:; " <>
          "connect-src 'self' ws: wss:; " <>
          "frame-ancestors 'none'"
    }

    plug :load_current_user

    plug EhsEnforcement.Consent.Plug,
      resource: EhsEnforcement.Consent.ConsentSettings,
      user_id_key: :current_user,
      skip_session_cache: true
  end

  pipeline :auth_required do
    plug EhsEnforcementWeb.Plugs.AuthHelpers, :require_authenticated_user
  end

  pipeline :admin_required do
    plug EhsEnforcementWeb.Plugs.AuthHelpers, :require_authenticated_user
    plug EhsEnforcementWeb.Plugs.AuthHelpers, :require_admin_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
  end

  pipeline :api_jwt_authenticated do
    plug :accepts, ["json"]
    plug EhsEnforcementWeb.Plugs.JwtAuth
  end

  # Flexible authentication - supports both JWT and session auth
  pipeline :api_flexible_authenticated do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_cookies
    plug EhsEnforcementWeb.Plugs.FlexibleAuth
  end

  # Health check pipeline - no authentication required
  pipeline :health do
    plug :accepts, ["json"]
  end

  # Authentication routes
  scope "/", EhsEnforcementWeb do
    pipe_through :browser

    sign_in_route(auth_routes_prefix: "/auth")
    sign_out_route(AuthController)
    auth_routes(AuthController, EhsEnforcement.Accounts.User, path: "/auth")
    reset_route(auth_routes_prefix: "/auth")
  end

  # Public routes - no authentication required
  scope "/", EhsEnforcementWeb do
    pipe_through :browser

    # Root route - redirect to cases for now (will become prompt-driven homepage in Phase 3)
    get "/", PageController, :home
    get "/home", PageController, :home

    live_session :public,
      on_mount: [
        AshAuthentication.Phoenix.LiveSession,
        {AshCookieConsent.LiveView.Hook, :load_consent}
      ] do
      # Landing page (/) and /dashboard are now served by Svelte frontend
      # API endpoint: /api/public/dashboard/stats (DashboardController)

      # Cases and Notices routes now served by Svelte frontend
      # API endpoints: /api/cases/:id and /api/notices/:id (for admin editing)

      # Read-only Offender Management Routes
      live "/offenders", OffenderLive.Index, :index
      live "/offenders/:id", OffenderLive.Show, :show

      # Read-only Legislation Management Routes
      live "/legislation", LegislationLive.Index, :index
      live "/legislation/:id", LegislationLive.Show, :show

      # Agency Management Routes (Open Access)
      live "/agencies", AgencyLive, :index

      # Reports & Analytics Routes (Open Access)
      live "/reports", ReportsLive.Index, :index
      live "/reports/offenders", ReportsLive.Offenders, :index

      # Static Pages (Open Access)
      live "/about", AboutLive, :index
      live "/docs", DocsLive, :index
      live "/privacy", PrivacyLive, :index
      live "/terms", TermsLive, :index
      live "/support", SupportLive, :index
      live "/contact", ContactLive, :index
    end

    # Non-LiveView routes
    # Cookie consent route
    post "/consent", ConsentController, :create
  end

  # Admin-only routes - require authentication and admin privileges
  scope "/", EhsEnforcementWeb do
    pipe_through [:browser, :admin_required]

    live_session :admin,
      on_mount: [
        AshAuthentication.Phoenix.LiveSession
      ] do
      # ============================================================================
      # ADMIN ROUTES MIGRATED TO SVELTE
      # ============================================================================
      # All admin routes have been migrated to Svelte 5 + TanStack Query.
      # The admin section now runs on the SvelteKit frontend.
      #
      # LiveView routes removed (2025-11-18):
      # - /admin - Admin dashboard
      # - /admin/agencies - Agency management (3 routes: index, new, edit)
      # - /admin/config - Configuration management (3 routes)
      # - /admin/duplicates - Duplicate detection
      # - /admin/offenders/reviews - Match review (2 routes)
      # - /admin/cases/:id/edit - Case editing
      # - /admin/notices/:id/edit - Notice editing
      # - /admin/offenders/:id/edit - Offender editing
      # - /admin/scrape - Scraping interface (3 routes)
      #
      # Total: 16 admin routes migrated
      # See: frontend/src/routes/admin/ for Svelte implementations
      # ============================================================================

      # Admin Legislation Management Routes
      # TODO: Implement Admin.LegislationLive modules (not yet created)
      # live "/admin/legislation", Admin.LegislationLive.Index, :index
      # live "/admin/legislation/new", Admin.LegislationLive.New, :new
      # live "/admin/legislation/:id/edit", Admin.LegislationLive.Edit, :edit
    end
  end

  # Health check endpoint - no authentication required
  scope "/", EhsEnforcementWeb do
    pipe_through :health

    get "/health", HealthController, :check
  end

  # API routes for local-first frontend
  scope "/api", EhsEnforcementWeb.Api do
    pipe_through :api

    # Public API endpoints
    get "/public/dashboard/stats", DashboardController, :stats
  end

  # Authenticated API routes (supports both JWT and session auth)
  scope "/api", EhsEnforcementWeb.Api do
    pipe_through :api_flexible_authenticated

    # Current user endpoint - supports both JWT (tenant users) and session (admin users)
    get "/user", CurrentUserController, :show
  end

  # Unified Data API and Admin API endpoints
  scope "/api", EhsEnforcementWeb do
    pipe_through :api

    # Unified data endpoint - combines Cases and Notices
    get "/unified-data", UnifiedDataController, :index

    # Natural Language Query Translation
    post "/nl-query", NLQueryController, :translate
    post "/nl-query/test", NLQueryController, :test
  end

  # Admin/Svelte Frontend API endpoints
  scope "/api", EhsEnforcementWeb.Api do
    pipe_through :api

    # Admin API endpoints
    get "/admin/stats", AdminController, :stats

    # Agency API endpoints
    get "/agencies", AgencyController, :index
    post "/agencies", AgencyController, :create
    patch "/agencies/:id", AgencyController, :update
    delete "/agencies/:id", AgencyController, :delete

    # Scraping API endpoints
    get "/scraping/sessions", ScrapingController, :index
    post "/scraping/start", ScrapingController, :start_scraping
    delete "/scraping/stop/:session_id", ScrapingController, :stop_scraping
    patch "/scraping/sessions/:id/complete", ScrapingController, :complete_session

    # Duplicates API endpoints
    get "/duplicates", DuplicatesController, :index
    delete "/duplicates", DuplicatesController, :delete_selected

    # Match Reviews API endpoints
    get "/match-reviews", MatchReviewsController, :index
    get "/match-reviews/:id", MatchReviewsController, :show
    post "/match-reviews/:id/approve", MatchReviewsController, :approve
    post "/match-reviews/:id/skip", MatchReviewsController, :skip
    post "/match-reviews/:id/flag", MatchReviewsController, :flag

    # Edit Forms API endpoints
    get "/cases/:id", CasesController, :show
    patch "/cases/:id", CasesController, :update
    get "/notices/:id", NoticesController, :show
    patch "/notices/:id", NoticesController, :update
    get "/offenders/:id", OffendersController, :show
    patch "/offenders/:id", OffendersController, :update

    # Offences API endpoints (list, view, create, update)
    get "/offences", OffencesController, :index
    get "/offences/:id", OffencesController, :show
    post "/offences", OffencesController, :create
    patch "/offences/:id", OffencesController, :update
  end

  # Server-Sent Events (SSE) for real-time scraping progress
  scope "/api/scraping", EhsEnforcementWeb do
    # No pipeline - SSE controller handles its own response headers
    get "/subscribe/:session_id", ScrapingSSEController, :subscribe
  end

  # Electric SQL Gatekeeper - JWT authenticated
  scope "/api/gatekeeper", EhsEnforcementWeb do
    pipe_through :api_jwt_authenticated

    post "/authorize_shape", GatekeeperController, :authorize_shape
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ehs_enforcement, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EhsEnforcementWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
