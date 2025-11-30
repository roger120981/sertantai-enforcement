defmodule EhsEnforcement.AI.Client.Ollama do
  @moduledoc """
  Ollama AI client implementation.

  Uses the Ollama API format (different from OpenAI-compatible).
  Works with the existing RunPod-hosted Ollama endpoint configured in dev.exs.

  ## Configuration

      config :ehs_enforcement, :ollama_url, "https://your-runpod-ollama-proxy.runpod.net"

      # Or set AI provider to ollama:
      config :ehs_enforcement, :ai_enrichment,
        provider: :ollama,
        ollama_model: "phi3"  # or "llama3.1", etc.
  """

  @behaviour EhsEnforcement.AI.Client

  require Logger

  @default_model "phi3"
  @default_timeout_ms 120_000

  @impl true
  def complete(messages, opts \\ []) do
    url = get_ollama_url()
    model = Keyword.get(opts, :model, get_default_model())
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    # Convert chat messages to a single prompt (Ollama /api/generate format)
    prompt = messages_to_prompt(messages)

    # Build request body
    body = %{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{
        temperature: Keyword.get(opts, :temperature, 0.7),
        num_predict: Keyword.get(opts, :max_tokens, 4096)
      }
    }

    # Add JSON format hint if requested
    body =
      if Keyword.get(opts, :json_mode, false) do
        Map.put(body, :format, "json")
      else
        body
      end

    start_time = System.monotonic_time(:millisecond)

    Logger.debug("Ollama request to #{url}/api/generate with model #{model}")

    case Req.post("#{url}/api/generate",
           json: body,
           receive_timeout: timeout_ms
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        latency_ms = System.monotonic_time(:millisecond) - start_time
        parse_response(response_body, model, latency_ms)

      {:ok, %{status: status, body: body}} ->
        Logger.error("Ollama error #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.error("Ollama request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def health_check do
    url = get_ollama_url()

    case Req.get("#{url}/api/tags", receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        models = body["models"] || []
        model_names = Enum.map(models, & &1["name"])
        {:ok, %{status: :available, provider: :ollama, models: model_names}}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp get_ollama_url do
    # First check ai_enrichment config, then fall back to ollama_url
    config = Application.get_env(:ehs_enforcement, :ai_enrichment, [])

    Keyword.get(config, :ollama_url) ||
      Application.get_env(:ehs_enforcement, :ollama_url) ||
      "http://localhost:11434"
  end

  defp get_default_model do
    # Allow configuring default model via ai_enrichment config
    config = Application.get_env(:ehs_enforcement, :ai_enrichment, [])
    Keyword.get(config, :ollama_model, @default_model)
  end

  defp messages_to_prompt(messages) do
    # Convert OpenAI-style messages to a single prompt string
    messages
    |> Enum.map(fn
      %{role: "system", content: content} ->
        "System: #{content}"

      %{role: "user", content: content} ->
        "User: #{content}"

      %{role: "assistant", content: content} ->
        "Assistant: #{content}"

      %{"role" => "system", "content" => content} ->
        "System: #{content}"

      %{"role" => "user", "content" => content} ->
        "User: #{content}"

      %{"role" => "assistant", "content" => content} ->
        "Assistant: #{content}"
    end)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n\nAssistant:")
  end

  defp parse_response(response, model, latency_ms) do
    case response do
      %{"response" => content} ->
        {:ok,
         %{
           content: content,
           model: model,
           usage: %{
             prompt_tokens: response["prompt_eval_count"] || 0,
             completion_tokens: response["eval_count"] || 0,
             total_tokens: (response["prompt_eval_count"] || 0) + (response["eval_count"] || 0)
           },
           latency_ms: latency_ms
         }}

      _ ->
        {:error, {:invalid_response, response}}
    end
  end
end
