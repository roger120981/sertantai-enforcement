defmodule EhsEnforcement.AI.Client.OpenAI do
  @moduledoc """
  OpenAI API client implementation.

  Direct integration with OpenAI's API for models like GPT-4.

  ## Configuration

      config :ehs_enforcement, :ai_enrichment,
        provider: :openai,
        openai_api_key: "sk-...",
        openai_model: "gpt-4-turbo",
        timeout_ms: 60_000,
        max_retries: 3
  """

  @behaviour EhsEnforcement.AI.Client

  require Logger

  @openai_api_url "https://api.openai.com/v1"

  @impl true
  def complete(messages, opts \\ []) do
    config = EhsEnforcement.AI.Client.get_config()
    api_key = Keyword.fetch!(config, :openai_api_key)
    model = Keyword.get(config, :openai_model, "gpt-4-turbo")
    timeout_ms = Keyword.get(config, :timeout_ms, 60_000)
    max_retries = Keyword.get(config, :max_retries, 3)

    # Build request body
    body =
      %{
        model: model,
        messages: messages,
        temperature: Keyword.get(opts, :temperature, 0.7),
        max_tokens: Keyword.get(opts, :max_tokens, 4096)
      }
      |> maybe_add_json_mode(opts)

    # Make request with retries
    start_time = System.monotonic_time(:millisecond)

    result =
      do_request_with_retry(
        "#{@openai_api_url}/chat/completions",
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
        Logger.error("OpenAI request failed: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def health_check do
    config = EhsEnforcement.AI.Client.get_config()

    with {:ok, api_key} <- fetch_config(config, :openai_api_key) do
      case Req.get("#{@openai_api_url}/models",
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

      {:ok, %{status: 429, headers: headers}} when retries_left > 0 ->
        # Rate limited - check retry-after header
        retry_after = get_retry_after(headers)
        Logger.warning("OpenAI rate limited, retrying in #{retry_after}s (#{retries_left} left)")
        Process.sleep(retry_after * 1_000)
        do_request_with_retry(url, api_key, body, timeout_ms, retries_left - 1)

      {:ok, %{status: status}} when status >= 500 and retries_left > 0 ->
        Logger.warning("OpenAI server error #{status}, retrying in 1s (#{retries_left} left)")
        Process.sleep(1_000)
        do_request_with_retry(url, api_key, body, timeout_ms, retries_left - 1)

      {:ok, %{status: status, body: body}} ->
        error_msg = get_in(body, ["error", "message"]) || "Unknown error"
        {:error, {:http_error, status, error_msg}}

      {:error, %Req.TransportError{reason: :timeout}} when retries_left > 0 ->
        Logger.warning("OpenAI request timeout, retrying (#{retries_left} retries left)")
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

  defp get_retry_after(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "retry-after" end)
    |> case do
      {_, value} -> String.to_integer(value)
      nil -> 2
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
