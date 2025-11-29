# AI Model Evaluation Framework

Framework for evaluating AI models for enforcement enrichment tasks.

## Overview

Provides systematic evaluation of candidate models to select the best option for production enrichment.

## Quick Start

```bash
# 1. Create balanced test dataset
mix evaluate.create_test_dataset

# 2. Set up RunPod credentials
export RUNPOD_API_KEY=your-key
export RUNPOD_LLAMA_70B_ENDPOINT=https://api.runpod.ai/v2/xxx/openai/v1

# 3. Run evaluation
mix evaluate.ai_models --model llama-3.1-70b

# 4. Review results
cat test/fixtures/ai_evaluation/results/comparison_report.md
```

## Test Dataset

**Location**: `test/fixtures/ai_evaluation/test_dataset.json`

### Selection Strategy

The dataset balances across multiple dimensions:

| Dimension | Distribution |
|-----------|--------------|
| **Temporal** | Recent (0-3mo), Medium (3-6mo), Older (6-12mo) |
| **Financial** | Low (<£10k), Medium (£10k-£100k), High (>£100k) |
| **Type** | Cases (15) + Notices (10) |

### Mix Task

```bash
mix evaluate.create_test_dataset
```

Creates 25 representative records for evaluation.

## Candidate Models

### Tier 1: High Accuracy (Recommended)

| Model | Parameters | Best For |
|-------|------------|----------|
| Llama 3.1 70B | 70B | Legal/regulatory analysis |
| Qwen 2.5 72B | 72B | Instruction following |

### Tier 2: Balanced

| Model | Parameters | Best For |
|-------|------------|----------|
| Llama 3.1 8B | 8B | Fast inference, lower cost |
| Mistral 7B | 7B | Efficient JSON output |

## Evaluation Metrics

### Accuracy (70% weight)

| Metric | Target | Weight |
|--------|--------|--------|
| Regulation identification | >80% | 20% |
| Benchmark accuracy | >75% | 15% |
| Pattern detection | >70% | 15% |
| Summary quality | >80% | 20% |

### Performance (20% weight)

| Metric | Target | Weight |
|--------|--------|--------|
| Latency (p95) | <30s | 10% |
| Success rate | >98% | 5% |
| Cost per case | <£0.50 | 5% |

### Reliability (10% weight)

| Metric | Target | Weight |
|--------|--------|--------|
| JSON parse success | >99% | 5% |
| Confidence calibration | Good | 5% |

## Running Evaluations

### Full Evaluation

```bash
mix evaluate.ai_models
```

Runs all configured models against full test dataset.

### Single Model

```bash
mix evaluate.ai_models --model llama-3.1-70b
```

### Quick Test (5 cases)

```bash
mix evaluate.ai_models --quick
```

## Output Files

Results saved to `test/fixtures/ai_evaluation/results/`:

| File | Contents |
|------|----------|
| `{model}_results.json` | Raw enrichment outputs |
| `{model}_metrics.json` | Performance statistics |
| `comparison_report.md` | Summary comparison |

### Metrics JSON Structure

```json
{
  "model": "llama-3.1-70b",
  "total_cases": 25,
  "successful": 24,
  "failed": 1,
  "success_rate": 0.96,
  "latency": {
    "avg_ms": 18500,
    "p95_ms": 25000,
    "p99_ms": 28000
  },
  "throughput_per_hour": 144,
  "estimated_cost_per_case": 0.35
}
```

## Scoring Rubric

### Total Score: 100 points

```
Accuracy:     70 points
  - Regulation links:    20
  - Benchmarks:          15
  - Patterns:            15
  - Summaries:           20

Performance:  20 points
  - Latency:             10
  - Success rate:         5
  - Cost:                 5

Reliability:  10 points
  - JSON parsing:         5
  - Calibration:          5
```

### Score Interpretation

| Score | Rating | Recommendation |
|-------|--------|----------------|
| 90-100 | Excellent | Production ready |
| 75-89 | Good | Minor tuning needed |
| 60-74 | Fair | Prompt engineering required |
| <60 | Poor | Consider alternative |

## Environment Variables

```bash
# RunPod endpoints (one per model)
RUNPOD_LLAMA_70B_ENDPOINT=https://api.runpod.ai/v2/xxx/openai/v1
RUNPOD_QWEN_72B_ENDPOINT=https://api.runpod.ai/v2/yyy/openai/v1
RUNPOD_LLAMA_8B_ENDPOINT=https://api.runpod.ai/v2/zzz/openai/v1

# Authentication
RUNPOD_API_KEY=your-api-key
```

## Cost Estimates

| Phase | Cases | Models | Estimated Cost |
|-------|-------|--------|----------------|
| Screening | 5 | 3 | ~$10 |
| Full eval | 25 | 3 | ~$50 |
| Production | 100/mo | 1 | ~$35/mo |

## Related Documentation

- [Enrichment Service](./enrichment.md) - Production service using selected model
- [RunPod Setup Guide](../research/runpod-setup-guide.md) - Endpoint configuration
- [AI Model Evaluation Framework](../plan/github-copilot-for-compliance/ai-model-evaluation-framework-for-enforcement-enrichment.md) - Full framework document
