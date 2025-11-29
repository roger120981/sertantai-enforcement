# AI Services Architecture

This directory documents the AI services and workflows used in the EHS Enforcement application.

## Overview

The application uses AI for two primary purposes:

| Service | Purpose | Provider | Location |
|---------|---------|----------|----------|
| [NL Query](./nl-query.md) | Natural language → TableKit filters | Ollama (Phi3) on RunPod | `nl_query_controller.ex` |
| [Enrichment](./enrichment.md) | Case/Notice contextual enrichment | RunPod/OpenAI (configurable) | `ai/enrichment_service.ex` |

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Frontend (Svelte)                        │
├─────────────────────────────────────────────────────────────────┤
│  Data Page                    │  Case/Notice Detail Pages       │
│  ┌─────────────────────┐      │  ┌─────────────────────┐        │
│  │ Natural Language    │      │  │ Enrichment Display  │        │
│  │ Query Input         │      │  │ (summaries, tags)   │        │
│  └──────────┬──────────┘      │  └──────────┬──────────┘        │
└─────────────┼─────────────────┼─────────────┼───────────────────┘
              │                               │
              ▼                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Phoenix Backend                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  POST /api/nl-query              GET /api/enrichments/:id       │
│  ┌─────────────────────┐         ┌─────────────────────┐        │
│  │ NLQueryController   │         │ Enrichment Resource │        │
│  └──────────┬──────────┘         └──────────┬──────────┘        │
│             │                               │                   │
│             ▼                               ▼                   │
│  ┌─────────────────────┐         ┌─────────────────────┐        │
│  │ Ollama Client       │         │ EnrichmentService   │        │
│  │ (direct HTTP)       │         │ (AI.Client behaviour)│       │
│  └──────────┬──────────┘         └──────────┬──────────┘        │
│             │                               │                   │
└─────────────┼───────────────────────────────┼───────────────────┘
              │                               │
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────────────┐
│  RunPod: Ollama/Phi3    │     │  AI Provider (configurable)     │
│  (NL Query Translation) │     │  ├─ RunPod (OpenAI-compatible)  │
│                         │     │  ├─ OpenAI (GPT-4)              │
└─────────────────────────┘     │  └─ Mock (testing)              │
                                └─────────────────────────────────┘
```

## Configuration

### Environment Variables

```bash
# NL Query Service (Ollama)
OLLAMA_URL=https://your-runpod-endpoint.proxy.runpod.net

# Enrichment Service
AI_ENRICHMENT_PROVIDER=runpod    # or: openai, mock
RUNPOD_API_KEY=your-api-key
RUNPOD_ENDPOINT=https://api.runpod.ai/v2/your-endpoint/openai/v1
OPENAI_API_KEY=sk-...            # if using OpenAI provider
OPENAI_MODEL=gpt-4-turbo         # default model for OpenAI
AI_ENRICHMENT_TIMEOUT_MS=60000   # request timeout
AI_ENRICHMENT_MAX_RETRIES=3      # retry attempts
```

### Development Defaults

In development, the enrichment service defaults to `:mock` provider, which returns realistic responses without API calls. The NL Query service requires a running Ollama endpoint.

## Service Comparison

| Aspect | NL Query | Enrichment |
|--------|----------|------------|
| **Trigger** | User input (real-time) | Background job (async) |
| **Latency requirement** | < 2s (interactive) | < 30s (batch acceptable) |
| **Model size** | Small (Phi3 ~3.8B) | Large (70B+ preferred) |
| **Output format** | JSON (TableKit config) | JSON (structured enrichment) |
| **Accuracy priority** | Medium (user can retry) | High (persisted data) |
| **Cost sensitivity** | High (frequent calls) | Low (< 100/month) |

## Future Considerations

1. **Unified Client Architecture** - Consider migrating NL Query to use `AI.Client` behaviour for consistency
2. **Model Evaluation** - Use `mix evaluate.ai_models` to benchmark different models
3. **Cost Monitoring** - Track token usage across both services
4. **Fallback Strategies** - Define degradation paths when AI services are unavailable

## Related Documentation

- [NL Query Service](./nl-query.md) - Detailed documentation for natural language query translation
- [Enrichment Service](./enrichment.md) - Detailed documentation for case/notice enrichment
- [Model Evaluation](./model-evaluation.md) - Framework for evaluating AI models
- [Prompt Engineering](./prompts.md) - System prompts and prompt design principles

## RunPod Setup Guides

Detailed setup guides for deploying AI models on RunPod community pods:

| Model | Guide | Use Case | Min GPU |
|-------|-------|----------|---------|
| [Llama 3.1 8B](./runpod-llama-8b.md) | Speed baseline | Fast inference, cost-effective | 1x RTX 4090 |
| [Llama 3.1 70B](./runpod-llama-70b.md) | Accuracy baseline | Complex reasoning, legal analysis | 2x RTX 4090 (AWQ) |
| [Qwen 2.5 72B](./runpod-qwen-72b.md) | Balanced option | Strong structured output, open license | 2x RTX 4090 (AWQ) |

### Quick Start

1. Choose a model based on your needs (start with 8B for testing)
2. Follow the setup guide to deploy a RunPod community pod
3. Set environment variables with your endpoint URL
4. Run `mix evaluate.ai_models --model <model-name>` to test
