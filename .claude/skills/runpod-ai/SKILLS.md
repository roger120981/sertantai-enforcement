---
name: runpod-ai-integration
description: Implements AI services using RunPod serverless endpoints with OpenAI-compatible APIs. Use when working with AI features, adding new AI workflows, configuring AI providers, or debugging AI service issues. Covers both NL Query and Enrichment services.
---

# RunPod AI Integration

This skill covers implementing and configuring AI services using RunPod serverless endpoints in the EHS Enforcement application.

## AI Service Architecture

Two AI services exist in the application:

| Service | Module | Provider | Purpose |
|---------|--------|----------|---------|
| NL Query | `NLQueryController` | Ollama (Phi3) on RunPod | Natural language → TableKit filters |
| Enrichment | `AI.EnrichmentService` | RunPod/OpenAI (configurable) | Case/Notice contextual enrichment |

## Prerequisites

```bash
# Required environment variables
export OLLAMA_URL=https://your-runpod-endpoint.proxy.runpod.net
export AI_ENRICHMENT_PROVIDER=runpod  # or: openai, mock
export RUNPOD_API_KEY=your-api-key
export RUNPOD_ENDPOINT=https://api.runpod.ai/v2/your-endpoint/openai/v1
```

## Using the AI Client Behaviour

All new AI services should use the `AI.Client` behaviour:

```elixir
defmodule EhsEnforcement.AI.Client do
  @callback complete(messages :: [message()], opts :: keyword()) ::
            {:ok, completion_response()} | {:error, term()}
  @callback health_check() :: {:ok, map()} | {:error, term()}
end
```

Get the configured client:

```elixir
client = EhsEnforcement.AI.Client.get_client()
# Returns: EhsEnforcement.AI.Client.RunPod | .OpenAI | .Mock

{:ok, response} = client.complete([
  %{role: "system", content: "You are a helpful assistant."},
  %{role: "user", content: "Summarize this case..."}
], model: "meta-llama/llama-3.3-70b-instruct")
```

## Adding a New AI Workflow

1. **Define the service module:**

```elixir
defmodule EhsEnforcement.AI.NewService do
  @moduledoc "New AI service description"
  
  alias EhsEnforcement.AI.Client
  
  def process(input, opts \\ []) do
    client = Client.get_client()
    messages = build_messages(input)
    
    with {:ok, response} <- client.complete(messages, opts),
         {:ok, parsed} <- parse_response(response) do
      {:ok, parsed}
    end
  end
  
  defp build_messages(input) do
    [
      %{role: "system", content: system_prompt()},
      %{role: "user", content: format_input(input)}
    ]
  end
  
  defp system_prompt do
    """
    You are an expert assistant. Return JSON only.
    """
  end
end
```

2. **Add configuration to runtime.exs** (if new provider options needed)

3. **Create tests using the Mock adapter:**

```elixir
defmodule EhsEnforcement.AI.NewServiceTest do
  use EhsEnforcement.DataCase, async: true
  
  # Mock adapter is default in test environment
  describe "process/2" do
    test "returns structured response" do
      {:ok, result} = NewService.process(input)
      assert result.field == expected_value
    end
  end
end
```

4. **Update documentation in `docs-dev/ai/`**

## Prompt Engineering Guidelines

### System Prompts

- Be explicit about output format (JSON, plain text)
- Include domain context for UK EHS enforcement
- Specify constraints (max tokens, required fields)

```elixir
defp system_prompt do
  """
  You are an expert in UK environmental, health, and safety enforcement.
  
  TASK: [Specific task description]
  
  OUTPUT FORMAT: Return valid JSON with this structure:
  {
    "field1": "string",
    "field2": ["array", "items"]
  }
  
  CONSTRAINTS:
  - Keep summaries under 200 words
  - Use UK English spelling
  - Reference specific regulations when applicable
  """
end
```

### Response Parsing

Always handle JSON parsing errors:

```elixir
defp parse_response(%{content: content}) do
  case Jason.decode(content) do
    {:ok, parsed} -> {:ok, parsed}
    {:error, _} -> {:error, :invalid_json}
  end
end
```

## Configuration Reference

Environment variables in `config/runtime.exs`:

```elixir
config :ehs_enforcement, :ai_enrichment,
  provider: :runpod,              # :runpod | :openai | :mock
  runpod_api_key: "...",          # RunPod API key
  runpod_endpoint: "...",         # OpenAI-compatible endpoint
  openai_api_key: "...",          # OpenAI API key (if using)
  openai_model: "gpt-4-turbo",    # Model for OpenAI provider
  timeout_ms: 60_000,             # Request timeout
  max_retries: 3                  # Retry attempts
```

## RunPod Endpoint Setup

RunPod serverless endpoints expose OpenAI-compatible APIs:

```
https://api.runpod.ai/v2/{endpoint_id}/openai/v1/chat/completions
```

Headers required:
- `Authorization: Bearer {RUNPOD_API_KEY}`
- `Content-Type: application/json`

## Troubleshooting

**"Connection refused" errors:**
- Verify RunPod endpoint is active (not scaled to zero)
- Check endpoint URL format includes `/openai/v1`

**Timeout errors:**
- Increase `timeout_ms` for large models (70B+)
- Consider cold start time for serverless endpoints

**Invalid JSON responses:**
- Strengthen system prompt JSON requirements
- Add response validation before parsing
- Use smaller models for structured output tasks

**Mock adapter not used in tests:**
- Ensure `AI_ENRICHMENT_PROVIDER` is unset or set to `mock`
- Default is `:mock` when env var not present

## Related Documentation

- [docs-dev/ai/README.md](../../../docs-dev/ai/README.md) - AI architecture overview
- [docs-dev/ai/nl-query.md](../../../docs-dev/ai/nl-query.md) - NL Query service details
- [docs-dev/ai/enrichment.md](../../../docs-dev/ai/enrichment.md) - Enrichment service details
- [docs-dev/ai/prompts.md](../../../docs-dev/ai/prompts.md) - Prompt engineering guide
