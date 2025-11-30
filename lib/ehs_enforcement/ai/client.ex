defmodule EhsEnforcement.AI.Client do
  @moduledoc """
  Behaviour for AI client implementations.

  This module defines the contract that all AI client adapters must implement.
  Currently supports:
  - `:runpod` - RunPod serverless endpoints (OpenAI-compatible)
  - `:openai` - OpenAI API directly
  - `:mock` - Mock client for testing

  ## Configuration

  Configure the AI client in `config/runtime.exs`:

      config :ehs_enforcement, :ai_enrichment,
        provider: :runpod,
        runpod_api_key: System.get_env("RUNPOD_API_KEY"),
        runpod_endpoint: System.get_env("RUNPOD_ENDPOINT"),
        timeout_ms: 60_000,
        max_retries: 3

  ## Usage

      # Get the configured client
      client = EhsEnforcement.AI.Client.get_client()

      # Make a completion request
      {:ok, response} = client.complete(messages, opts)
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type completion_response :: %{
          content: String.t(),
          model: String.t(),
          usage: %{
            prompt_tokens: non_neg_integer(),
            completion_tokens: non_neg_integer(),
            total_tokens: non_neg_integer()
          },
          latency_ms: non_neg_integer()
        }

  @doc """
  Send a chat completion request to the AI model.

  ## Parameters

  - `messages` - List of message maps with `:role` and `:content` keys
  - `opts` - Optional parameters:
    - `:temperature` - Sampling temperature (0.0-2.0, default: 0.7)
    - `:max_tokens` - Maximum tokens in response (default: 4096)
    - `:json_mode` - Request JSON output format (default: false)

  ## Returns

  - `{:ok, completion_response()}` on success
  - `{:error, reason}` on failure
  """
  @callback complete(messages :: [message()], opts :: keyword()) ::
              {:ok, completion_response()} | {:error, term()}

  @doc """
  Check if the client is properly configured and available.

  ## Returns

  - `{:ok, %{model: String.t(), status: :available}}` if healthy
  - `{:error, reason}` if unavailable
  """
  @callback health_check() :: {:ok, map()} | {:error, term()}

  @doc """
  Get the configured AI client module based on application config.

  Returns the appropriate client module based on the `:provider` setting.
  """
  @spec get_client() :: module()
  def get_client do
    config = Application.get_env(:ehs_enforcement, :ai_enrichment, [])
    provider = Keyword.get(config, :provider, :mock)

    case provider do
      :runpod -> EhsEnforcement.AI.Client.RunPod
      :openai -> EhsEnforcement.AI.Client.OpenAI
      :ollama -> EhsEnforcement.AI.Client.Ollama
      :mock -> EhsEnforcement.AI.Client.Mock
      other -> raise "Unknown AI provider: #{inspect(other)}"
    end
  end

  @doc """
  Get the current AI configuration.
  """
  @spec get_config() :: keyword()
  def get_config do
    Application.get_env(:ehs_enforcement, :ai_enrichment, [])
  end
end
