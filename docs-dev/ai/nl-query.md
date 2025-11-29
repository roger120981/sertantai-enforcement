# NL Query Service

Natural language query translation for the Data page TableKit interface.

## Overview

Converts user queries like "show me HSE cases with fines over £50,000" into TableKit filter configuration.

## Architecture

```
User Input → NLQueryController → Ollama/Phi3 → TableKit Config → Frontend
```

## Endpoint

```
POST /api/nl-query
Content-Type: application/json

{
  "query": "HSE cases with fines over 50000",
  "prompt_version": "v5"  // optional, defaults to latest
}
```

### Response

```json
{
  "filters": [
    {"field": "agency_code", "operator": "eq", "value": "hse"},
    {"field": "offence_fine", "operator": "gt", "value": 50000}
  ],
  "sort": [
    {"field": "offence_fine", "direction": "desc"}
  ],
  "columns": ["case_reference", "offender_name", "offence_fine", "offence_action_date"]
}
```

## Implementation

**File**: `lib/ehs_enforcement_web/controllers/nl_query_controller.ex`

### Key Functions

- `translate/2` - Main endpoint for query translation
- `test/2` - Test endpoint for prompt version comparison

### Supported Fields

| Field | Type | Example Query |
|-------|------|---------------|
| `agency_code` | enum | "HSE cases", "EA enforcement" |
| `record_type` | enum | "court cases", "notices" |
| `offence_fine` | number | "fines over £50,000" |
| `offence_action_date` | date | "cases from 2024" |
| `offender_name` | string | "cases against Tesco" |
| `case_reference` | string | "case ref ABC123" |

### Operators

- `eq` - equals
- `neq` - not equals
- `gt` / `gte` - greater than (or equal)
- `lt` / `lte` - less than (or equal)
- `contains` - string contains
- `starts_with` - string starts with

## Configuration

```elixir
# config/dev.exs
config :ehs_enforcement, :ollama_url, "https://xxx.proxy.runpod.net"
```

## AI Model

**Model**: Phi3 (3.8B parameters)
**Host**: Ollama on RunPod serverless
**Latency**: ~1-2 seconds typical

### Why Phi3?

- Small enough for low-latency interactive use
- Good instruction-following for structured output
- Cost-effective for frequent queries
- Runs well on RunPod serverless

## Prompt Versions

The service supports multiple prompt versions for A/B testing:

| Version | Description |
|---------|-------------|
| v1 | Basic field mapping |
| v2 | Added operator support |
| v3 | Improved date handling |
| v4 | Better number parsing |
| v5 | Current production (enhanced examples) |

Use the test endpoint to compare versions:

```bash
curl -X POST http://localhost:4002/api/nl-query/test \
  -H "Content-Type: application/json" \
  -d '{"query": "HSE fines over 50k", "versions": ["v4", "v5"]}'
```

## Error Handling

| Error | Response | User Experience |
|-------|----------|-----------------|
| AI timeout | 504 | "Query took too long, please try again" |
| Parse failure | 422 | "Couldn't understand query, try rephrasing" |
| Invalid JSON | 422 | Falls back to empty filters |

## Future Improvements

1. **Migrate to AI.Client** - Use the shared client behaviour for consistency
2. **Caching** - Cache common queries to reduce API calls
3. **Feedback loop** - Track which queries work/fail for prompt improvement
4. **Streaming** - Consider streaming responses for better UX
