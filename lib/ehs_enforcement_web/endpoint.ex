defmodule EhsEnforcementWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ehs_enforcement

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_ehs_enforcement_key",
    signing_salt: "71P5v+1J",
    same_site: "Lax",
    secure: Application.compile_env(:ehs_enforcement, :force_ssl, false)
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [session: @session_options],
      timeout: 45_000,
      transport_log: false,
      compress: false
    ],
    longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :ehs_enforcement,
    gzip: false,
    only: EhsEnforcementWeb.static_paths()

  # Tidewave MCP for AI assistance during development
  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :ehs_enforcement
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # CORS configuration for frontend (localhost:5173)
  # credentials: true is required for session cookies to work cross-origin
  plug CORSPlug,
    origin: ["http://localhost:5173"],
    credentials: true

  plug Plug.Session, @session_options
  plug EhsEnforcementWeb.Router
end
