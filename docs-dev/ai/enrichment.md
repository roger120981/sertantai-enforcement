# Enrichment Service

AI-powered contextual enrichment for enforcement cases and notices.

## Overview

Generates comprehensive contextual intelligence for enforcement actions including:
- Regulation cross-references
- Industry benchmarks
- Pattern detection
- Plain language summaries
- Auto-generated tags

## Architecture

```
Case/Notice Created → Oban Job → EnrichmentService → AI Provider → Enrichment Record
```

## Implementation

### Core Module

**File**: `lib/ehs_enforcement/ai/enrichment_service.ex`

```elixir
# Enrich a case
{:ok, enrichment} = EnrichmentService.enrich_case(case)

# Enrich a notice
{:ok, enrichment} = EnrichmentService.enrich_notice(notice)

# Preview without saving
{:ok, data} = EnrichmentService.generate_enrichment(case)

# Check service health
{:ok, %{status: :available}} = EnrichmentService.health_check()
```

### Client Architecture

**Behaviour**: `lib/ehs_enforcement/ai/client.ex`

```elixir
@callback complete(messages, opts) :: {:ok, response} | {:error, term}
@callback health_check() :: {:ok, map} | {:error, term}
```

**Adapters**:
- `AI.Client.RunPod` - OpenAI-compatible API on RunPod serverless
- `AI.Client.OpenAI` - Direct OpenAI API
- `AI.Client.Mock` - Testing/development (no API calls)

## Enrichment Schema

**Resource**: `lib/ehs_enforcement/enforcement/resources/enrichment.ex`

| Field | Type | Description |
|-------|------|-------------|
| `regulation_links` | array of maps | Primary & related regulation references |
| `benchmark_analysis` | map | Fine percentiles, similar cases, severity |
| `pattern_detection` | map | Industry patterns, trends, repeat offender |
| `layperson_summary` | string | Plain English summary (150-300 words) |
| `professional_summary` | string | Technical summary (200-400 words) |
| `auto_tags` | array of strings | Categorization tags |
| `confidence_scores` | map | 0.0-1.0 confidence per section |
| `model_version` | string | AI model used |
| `processing_time_ms` | integer | Generation time |

### Example Enrichment

```json
{
  "regulation_links": [
    {
      "type": "primary",
      "title": "Health and Safety at Work Act 1974",
      "section": "Section 2(1)",
      "relevance": "General duty of employer"
    }
  ],
  "benchmark_analysis": {
    "fine_percentile": 75,
    "similar_cases_count": 23,
    "average_fine_similar": 45000,
    "severity_assessment": "above average"
  },
  "pattern_detection": {
    "industry_pattern": "Construction sector - fall from height",
    "recurring_violation": "Inadequate edge protection",
    "trend_analysis": "Increasing enforcement Q3-Q4 2024"
  },
  "layperson_summary": "A company was fined for failing to...",
  "professional_summary": "Breach of HSWA 1974 Section 2(1)...",
  "auto_tags": ["workplace_safety", "construction", "fall_from_height"],
  "confidence_scores": {
    "regulation_links": 0.92,
    "benchmark_analysis": 0.78,
    "pattern_detection": 0.65,
    "summaries": 0.88,
    "tags": 0.91
  }
}
```

## Configuration

```bash
# Provider selection
AI_ENRICHMENT_PROVIDER=runpod  # runpod | openai | mock

# RunPod (OpenAI-compatible)
RUNPOD_API_KEY=your-key
RUNPOD_ENDPOINT=https://api.runpod.ai/v2/xxx/openai/v1

# OpenAI (alternative)
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4-turbo

# Shared settings
AI_ENRICHMENT_TIMEOUT_MS=60000
AI_ENRICHMENT_MAX_RETRIES=3
```

## AI Models

### Recommended Models

| Model | Provider | Use Case |
|-------|----------|----------|
| Llama 3.1 70B | RunPod | Production (best accuracy) |
| Qwen 2.5 72B | RunPod | Alternative (good balance) |
| GPT-4 Turbo | OpenAI | Fallback (highest cost) |

### Model Evaluation

Use the evaluation framework to benchmark models:

```bash
# Create test dataset
mix evaluate.create_test_dataset

# Run evaluation
mix evaluate.ai_models --model llama-3.1-70b

# Quick test (5 cases only)
mix evaluate.ai_models --quick
```

Results saved to `test/fixtures/ai_evaluation/results/`.

## Prompt Engineering

### Case Prompt Structure

```
System: You are a UK EHS compliance expert...
User: Analyze this enforcement case:
  - Offender: {name}
  - Fine: £{amount}
  - Breaches: {description}
  
Provide JSON with: regulation_links, benchmark_analysis, 
pattern_detection, summaries, auto_tags, confidence_scores
```

### Notice Prompt Structure

Similar but focused on:
- Compliance timelines (not fines)
- Escalation likelihood
- Compliance requirements (not legal outcomes)

## Background Processing

**Status**: Pending (Day 5 implementation)

Will use Oban worker to:
1. Trigger on Case/Notice creation
2. Queue enrichment job
3. Process asynchronously
4. Store result in `enrichments` table

## Error Handling

| Error | Handling |
|-------|----------|
| AI timeout | Retry with backoff (max 3 attempts) |
| Rate limit | Wait for retry-after, then retry |
| Parse error | Log error, return `{:error, :json_parse_error}` |
| Server error (5xx) | Retry with backoff |

## Testing

```bash
# Run enrichment tests
mix test test/ehs_enforcement/ai/

# 27 tests covering:
# - Client behaviour and adapters
# - Case enrichment
# - Notice enrichment
# - Error handling
# - JSON parsing
```

## Relationships

- **Case** → has_one Enrichment (via `case_id`)
- **Notice** → has_one Enrichment (via `notice_id`)
- **EnrichmentValidation** → belongs_to Enrichment (professional feedback)
