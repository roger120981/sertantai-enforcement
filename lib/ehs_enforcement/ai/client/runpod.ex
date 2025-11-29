defmodule EhsEnforcement.AI.Client.RunPod do
  @moduledoc """
  RunPod AI client implementation using OpenAI-compatible API.

  RunPod serverless endpoints provide an OpenAI-compatible API interface,
  making it easy to use open-source models like Llama, Qwen, and Mistral.

  ## Configuration

      config :ehs_enforcement, :ai_enrichment,
        provider: :runpod,
        runpod_api_key: "your-api-key",
        runpod_endpoint: "https://api.runpod.ai/v2/your-endpoint-id/openai/v1",
        timeout_ms: 60_000,
        max_retries: 3

  ## RunPod Endpoint Setup

  1. Create a serverless endpoint on RunPod with your model
  2. Enable OpenAI-compatible mode
  3. Use the endpoint URL from the dashboard
  """

  @behaviour EhsEnforcement.AI.Client

  require Logger

  @impl true
  def complete(messages, opts \\ []) do
    config = EhsEnforcement.AI.Client.get_config()
    api_key = Keyword.fetch!(config, :runpod_api_key)
    endpoint = Keyword.fetch!(config, :runpod_endpoint)
    timeout_ms = Keyword.get(config, :timeout_ms, 60_000)
    max_retries = Keyword.get(config, :max_retries, 3)

    # Build request body
    body =
      %{
        messages: messages,
        temperature: Keyword.get(opts, :temperature, 0.7),
        max_tokens: Keyword.get(opts, :max_tokens, 4096)
      }
      |> maybe_add_json_mode(opts)

    # Make request with retries
    start_time = System.monotonic_time(:millisecond)

    result =
      do_request_with_retry(
        endpoint <> "/chat/completions",
        api_key,
        body,
        timeout_ms,
        max_retries
      )

    latency_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, response} ->
        parse_response(response, latency_ms)

      {:error, reason} = error ->
        Logger.error("RunPod AI request failed: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def health_check do
    config = EhsEnforcement.AI.Client.get_config()

    with {:ok, api_key} <- fetch_config(config, :runpod_api_key),
         {:ok, endpoint} <- fetch_config(config, :runpod_endpoint) do
      # Simple health check - list models endpoint
      case Req.get("#{endpoint}/models",
             headers: [{"Authorization", "Bearer #{api_key}"}],
             receive_timeout: 10_000
           ) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, %{status: :available, models: body["data"] || []}}

        {:ok, %{status: status}} ->
          {:error, {:http_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Private functions

  defp do_request_with_retry(url, api_key, body, timeout_ms, retries_left) do
    case Req.post(url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{api_key}"},
             {"Content-Type", "application/json"}
           ],
           receive_timeout: timeout_ms
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 429}} when retries_left > 0 ->
        # Rate limited - wait and retry
        Logger.warning("RunPod rate limited, retrying in 2s (#{retries_left} retries left)")
        Process.sleep(2_000)
        do_request_with_retry(url, api_key, body, timeout_ms, retries_left - 1)

      {:ok, %{status: status}} when status >= 500 and retries_left > 0 ->
        # Server error - wait and retry
        Logger.warning(
          "RunPod server error #{status}, retrying in 1s (#{retries_left} retries left)"
        )

        Process.sleep(1_000)
        do_request_with_retry(url, api_key, body, timeout_ms, retries_left - 1)

      {:ok, %{status: status, body: body}} ->
        error_msg = body["error"]["message"] || "Unknown error"
        {:error, {:http_error, status, error_msg}}

      {:error, %Req.TransportError{reason: :timeout}} when retries_left > 0 ->
        Logger.warning("RunPod request timeout, retrying (#{retries_left} retries left)")
        do_request_with_retry(url, api_key, body, timeout_ms, retries_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response(response, latency_ms) do
    case response do
      %{"choices" => [%{"message" => %{"content" => content}} | _], "usage" => usage} ->
        {:ok,
         %{
           content: content,
           model: response["model"] || "unknown",
           usage: %{
             prompt_tokens: usage["prompt_tokens"] || 0,
             completion_tokens: usage["completion_tokens"] || 0,
             total_tokens: usage["total_tokens"] || 0
           },
           latency_ms: latency_ms
         }}

      _ ->
        {:error, {:invalid_response, response}}
    end
  end

  defp maybe_add_json_mode(body, opts) do
    if Keyword.get(opts, :json_mode, false) do
      Map.put(body, :response_format, %{type: "json_object"})
    else
      body
    end
  end

  defp fetch_config(config, key) do
    case Keyword.get(config, key) do
      nil -> {:error, {:missing_config, key}}
      "" -> {:error, {:missing_config, key}}
      value -> {:ok, value}
    end
  end
end
