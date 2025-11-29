# Prompt Engineering Guide

Design principles and templates for AI prompts in the EHS Enforcement application.

## General Principles

### 1. Structured Output

Always request JSON output with explicit schema:

```
You MUST respond with valid JSON in this exact structure:
{
  "field_name": <type>,
  ...
}
```

### 2. Domain Context

Establish expertise upfront:

```
You are a UK environmental, health, and safety compliance expert 
specializing in enforcement action analysis.
```

### 3. Confidence Scores

Request self-assessment:

```
Include confidence scores (0.0-1.0) for each section.
Be honest about uncertainty - lower scores when information is limited.
```

### 4. Dual Audiences

Generate content for different readers:

```
- layperson_summary: Grade 8-10 reading level, no jargon
- professional_summary: Technical precision, legal citations
```

## NL Query Prompts

### Purpose
Convert natural language to TableKit filter configuration.

### Current Version (v5)

```
You are a query parser for an enforcement database. Convert the user's 
natural language query into a structured filter configuration.

Available fields:
- agency_code: "hse" | "ea" | "sepa" | "nrw"
- record_type: "case" | "notice"
- offence_fine: number (in GBP)
- offence_action_date: date (YYYY-MM-DD)
- offender_name: string

Operators: eq, neq, gt, gte, lt, lte, contains, starts_with

Examples:
- "HSE cases" → {"field": "agency_code", "operator": "eq", "value": "hse"}
- "fines over £50,000" → {"field": "offence_fine", "operator": "gt", "value": 50000}
- "cases from 2024" → {"field": "offence_action_date", "operator": "gte", "value": "2024-01-01"}

Respond with JSON only:
{
  "filters": [...],
  "sort": [...],
  "columns": [...]
}
```

### Design Decisions

1. **Explicit field list** - Model knows exactly what's available
2. **Operator examples** - Shows expected format
3. **Value normalization** - Numbers without currency symbols
4. **JSON-only response** - No explanation text

## Enrichment Prompts

### Case Enrichment

```
You are a UK environmental, health, and safety compliance expert 
specializing in enforcement action analysis.

Your task is to analyze enforcement cases (court prosecutions) and 
provide structured enrichment data.

## Required Output Format (JSON)

{
  "regulation_links": {
    "primary_regulations": [
      {"title": "...", "section": "...", "relevance": "..."}
    ],
    "related_regulations": [...]
  },
  "benchmark_analysis": {
    "fine_percentile": <1-100>,
    "similar_cases_count": <number>,
    "average_fine_similar": <GBP>,
    "severity_assessment": "<below average|average|above average|severe>"
  },
  "pattern_detection": {
    "industry_pattern": "...",
    "recurring_violation": "...",
    "trend_analysis": "...",
    "repeat_offender": <boolean>
  },
  "layperson_summary": "150-300 words, plain English",
  "professional_summary": "200-400 words, technical",
  "auto_tags": ["tag1", "tag2"],
  "confidence_scores": {
    "regulation_links": <0.0-1.0>,
    ...
  }
}

## Guidelines

1. Identify specific UK legislation (HSWA 1974, MHSWR 1999, etc.)
2. Compare to typical fines for similar violations
3. Use lowercase underscore tags (e.g., "fall_from_height")
4. Be honest about uncertainty in confidence scores
```

### Notice Enrichment

Similar structure but focused on:
- Compliance timelines instead of fines
- Escalation likelihood
- Compliance requirements

```
"benchmark_analysis": {
  "typical_compliance_period": "...",
  "escalation_likelihood": "<low|medium|high>",
  "similar_notices_count": <number>
}
```

## Prompt Versioning

### Strategy

1. Keep prompts in version control (embedded in code)
2. Support A/B testing via `prompt_version` parameter
3. Log which version generated each response
4. Track success rates per version

### Version History

| Version | Date | Changes |
|---------|------|---------|
| v1 | 2024-10 | Initial prompt |
| v2 | 2024-10 | Added operator support |
| v3 | 2024-11 | Improved date handling |
| v4 | 2024-11 | Better number parsing |
| v5 | 2024-11 | Enhanced examples, current production |

## Testing Prompts

### Quick Test

```elixir
# In IEx
alias EhsEnforcement.AI.Client.Mock
messages = [
  %{role: "system", content: "..."},
  %{role: "user", content: "..."}
]
{:ok, response} = Mock.complete(messages, json_mode: true)
```

### Evaluation

```bash
# Compare prompt versions
curl -X POST http://localhost:4002/api/nl-query/test \
  -d '{"query": "...", "versions": ["v4", "v5"]}'
```

## Common Issues

### JSON Parse Failures

**Problem**: Model returns markdown code blocks
```
```json
{...}
```
```

**Solution**: Strip markdown wrapper in response parsing

### Hallucinated Fields

**Problem**: Model invents fields not in schema

**Solution**: Explicit "ONLY include these fields" instruction

### Inconsistent Confidence

**Problem**: Always returns 0.9+ confidence

**Solution**: Add examples of low-confidence scenarios

## Model-Specific Notes

### Llama 3.1

- Excellent instruction following
- May be verbose in summaries (use word limits)

### Phi3

- Good for structured output
- Struggles with complex reasoning
- Best for simple query translation

### GPT-4

- Most reliable JSON output
- Highest cost
- Good fallback option
