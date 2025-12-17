import Config

# Load environment variables from .env.local in development
if config_env() in [:dev, :test] do
  case File.read(".env.local") do
    {:ok, content} ->
      content
      |> String.split("\n")
      |> Enum.each(fn line ->
        line = String.trim(line)

        if line != "" and not String.starts_with?(line, "#") do
          case String.split(line, "=", parts: 2) do
            [key, value] -> System.put_env(String.trim(key), String.trim(value))
            _ -> :ok
          end
        end
      end)

    {:error, _} ->
      # .env.local file doesn't exist, continue without it
      :ok
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Development database configuration from environment variables
if config_env() == :dev do
  if db_username = System.get_env("DB_USERNAME") do
    config :ehs_enforcement, EhsEnforcement.Repo,
      username: db_username,
      password: System.get_env("DB_PASSWORD") || "postgres",
      hostname: System.get_env("DB_HOSTNAME") || "localhost",
      port: String.to_integer(System.get_env("DB_PORT") || "5432"),
      database: System.get_env("DB_NAME") || "sertantai_enforcement_dev"
  end

  # GitHub OAuth configuration
  config :ehs_enforcement, :github_oauth,
    client_id:
      System.get_env("EHS_ENFORCEMENT_GITHUB_CLIENT_ID") || System.get_env("GITHUB_CLIENT_ID"),
    client_secret:
      System.get_env("EHS_ENFORCEMENT_GITHUB_CLIENT_SECRET") ||
        System.get_env("GITHUB_CLIENT_SECRET"),
    redirect_uri:
      System.get_env("GITHUB_REDIRECT_URI") || "http://localhost:4002/auth/user/github/callback"

  # GitHub admin configuration
  config :ehs_enforcement, :github_admin,
    owner: System.get_env("GITHUB_REPO_OWNER"),
    repo: System.get_env("GITHUB_REPO_NAME"),
    access_token: System.get_env("GITHUB_ACCESS_TOKEN"),
    allowed_users:
      System.get_env("GITHUB_ALLOWED_USERS", "") |> String.split(",") |> Enum.map(&String.trim/1)

  # Token signing secret
  config :ehs_enforcement,
         :token_signing_secret,
         System.get_env("TOKEN_SIGNING_SECRET") || "dev-only-secret-change-in-production"

  # Companies House API configuration
  config :ehs_enforcement, :companies_house, api_key: System.get_env("COMPANIES_HOUSE_API_KEY")

  # AI Enrichment Service configuration
  # Supports multiple providers: :runpod, :openai, :mock
  config :ehs_enforcement, :ai_enrichment,
    provider: String.to_atom(System.get_env("AI_ENRICHMENT_PROVIDER") || "mock"),
    # RunPod configuration (OpenAI-compatible API)
    runpod_api_key: System.get_env("RUNPOD_API_KEY"),
    runpod_endpoint: System.get_env("RUNPOD_ENDPOINT"),
    # OpenAI configuration (alternative provider)
    openai_api_key: System.get_env("OPENAI_API_KEY"),
    openai_model: System.get_env("OPENAI_MODEL") || "gpt-4-turbo",
    # Shared settings
    timeout_ms: String.to_integer(System.get_env("AI_ENRICHMENT_TIMEOUT_MS") || "60000"),
    max_retries: String.to_integer(System.get_env("AI_ENRICHMENT_MAX_RETRIES") || "3")
end

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ehs_enforcement start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ehs_enforcement, EhsEnforcementWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :ehs_enforcement, EhsEnforcement.Repo,
    # SSL configuration from DATABASE_URL parameters (e.g., ?ssl=false)
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    # Connection pool configuration for production
    pool_timeout: 30_000,
    ownership_timeout: 60_000,
    timeout: 60_000

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4002")

  config :ehs_enforcement, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ehs_enforcement, EhsEnforcementWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    # Allow WebSocket connections from production domain
    # This is CRITICAL for WebSocket connections to work behind proxies
    check_origin: [
      "//ehs-enforcement.sertantai.com",
      "//www.ehs-enforcement.sertantai.com",
      "https://ehs-enforcement.sertantai.com",
      "https://www.ehs-enforcement.sertantai.com"
    ]

  # GitHub OAuth configuration for production
  config :ehs_enforcement, :github_oauth,
    client_id:
      System.get_env("GITHUB_CLIENT_ID") ||
        raise("GITHUB_CLIENT_ID environment variable is missing"),
    client_secret:
      System.get_env("GITHUB_CLIENT_SECRET") ||
        raise("GITHUB_CLIENT_SECRET environment variable is missing"),
    redirect_uri:
      System.get_env("GITHUB_REDIRECT_URI") || "https://#{host}/auth/user/github/callback"

  # GitHub admin configuration for production
  config :ehs_enforcement, :github_admin,
    owner: System.get_env("GITHUB_REPO_OWNER"),
    repo: System.get_env("GITHUB_REPO_NAME"),
    access_token: System.get_env("GITHUB_ACCESS_TOKEN"),
    allowed_users:
      System.get_env("GITHUB_ALLOWED_USERS", "") |> String.split(",") |> Enum.map(&String.trim/1)

  # Token signing secret for production
  config :ehs_enforcement,
         :token_signing_secret,
         System.get_env("TOKEN_SIGNING_SECRET") ||
           raise("TOKEN_SIGNING_SECRET environment variable is missing")

  # Companies House API configuration for production
  config :ehs_enforcement, :companies_house, api_key: System.get_env("COMPANIES_HOUSE_API_KEY")

  # AI Enrichment Service configuration for production
  # Requires either RunPod or OpenAI API key to be set
  config :ehs_enforcement, :ai_enrichment,
    provider: String.to_atom(System.get_env("AI_ENRICHMENT_PROVIDER") || "runpod"),
    # RunPod configuration (OpenAI-compatible API)
    runpod_api_key: System.get_env("RUNPOD_API_KEY"),
    runpod_endpoint: System.get_env("RUNPOD_ENDPOINT"),
    # OpenAI configuration (alternative provider)
    openai_api_key: System.get_env("OPENAI_API_KEY"),
    openai_model: System.get_env("OPENAI_MODEL") || "gpt-4-turbo",
    # Shared settings
    timeout_ms: String.to_integer(System.get_env("AI_ENRICHMENT_TIMEOUT_MS") || "60000"),
    max_retries: String.to_integer(System.get_env("AI_ENRICHMENT_MAX_RETRIES") || "3")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ehs_enforcement, EhsEnforcementWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :ehs_enforcement, EhsEnforcementWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :ehs_enforcement, EhsEnforcement.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
