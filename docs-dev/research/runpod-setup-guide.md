# RunPod Setup Guide for AI Model Evaluation

**Created**: 2025-11-22
**Purpose**: Step-by-step guide to set up RunPod.io for enforcement case enrichment evaluation
**Related**: `ai-model-evaluation-framework.md`, GitHub Issue #2

---

## Overview

This guide walks through setting up AI model endpoints on RunPod.io for evaluating case enrichment quality. You'll create serverless endpoints for multiple models and configure the evaluation scripts.

---

## Prerequisites

- [x] RunPod.io account created
- [ ] Credit card added (for serverless endpoints)
- [ ] RunPod API key generated
- [ ] HTTPoison dependency added to mix.exs

---

## Step 1: Add HTTPoison Dependency

Edit `mix.exs` to add the HTTP client:

```elixir
defp deps do
  [
    # ... existing deps ...
    {:httpoison, "~> 2.2"}
  ]
end
```

Then run:
```bash
mix deps.get
```

---

## Step 2: Generate RunPod API Key

1. Log into https://runpod.io
2. Navigate to **Settings** → **API Keys**
3. Click **+ API Key**
4. Name: `sertantai-enforcement-eval`
5. Permissions: **Read & Write** (needed for serverless endpoints)
6. Copy the generated key (starts with `runpod-...`)

**Save to `.env` file**:
```bash
# Add to .env (or .env.local)
export RUNPOD_API_KEY="runpod-YOUR-KEY-HERE"
```

**Load environment**:
```bash
source .env
```

---

## Step 3: Create Serverless Endpoints

### Why Serverless?
- **Pay-per-second**: Only charged when models are running
- **Auto-scaling**: Handles burst requests
- **No idle costs**: Perfect for evaluation workload (intermittent usage)

### Recommended Models

#### Option 1: Meta Llama 3.1 70B Instruct
**Best for**: High accuracy, complex reasoning

1. Go to **Serverless** → **+ New Endpoint**
2. Template: Search "Llama 3.1 70B"
3. Select: `runpod/llama-3.1-70b-instruct`
4. Configuration:
   - Name: `llama-3.1-70b-enforcement`
   - GPUs: 2x A100 (80GB) or 4x A40 (48GB)
   - Max workers: 1 (evaluation doesn't need scale)
   - Idle timeout: 60 seconds
5. Deploy
6. Copy **Endpoint URL** (format: `https://api.runpod.ai/v2/{endpoint_id}/...`)

**Cost estimate**: ~$0.50-0.80 per 1000 tokens

#### Option 2: Qwen 2.5 72B Instruct
**Best for**: Balanced accuracy and speed

1. **Serverless** → **+ New Endpoint**
2. Template: Search "Qwen 2.5 72B"
3. Select: Community template or use custom image
4. Configuration:
   - Name: `qwen-2.5-72b-enforcement`
   - GPUs: 2x A100 (80GB)
   - Max workers: 1
   - Idle timeout: 60 seconds
5. Deploy
6. Copy **Endpoint URL**

**Cost estimate**: ~$0.40-0.60 per 1000 tokens

#### Option 3: Meta Llama 3.1 8B Instruct
**Best for**: Fast, cost-effective

1. **Serverless** → **+ New Endpoint**
2. Template: Search "Llama 3.1 8B"
3. Select: `runpod/llama-3.1-8b-instruct`
4. Configuration:
   - Name: `llama-3.1-8b-enforcement`
   - GPUs: 1x RTX 4090 or 1x A40
   - Max workers: 1
   - Idle timeout: 60 seconds
5. Deploy
6. Copy **Endpoint URL**

**Cost estimate**: ~$0.05-0.10 per 1000 tokens

---

## Step 4: Test Endpoints

### Quick Test with cURL

```bash
# Test Llama 70B endpoint
curl -X POST https://api.runpod.ai/v2/{endpoint_id}/runsync \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "prompt": "Explain the Health and Safety at Work Act 1974 in one sentence.",
      "max_tokens": 100,
      "temperature": 0.3
    }
  }'
```

Expected response:
```json
{
  "delayTime": 234,
  "executionTime": 1823,
  "id": "...",
  "output": {
    "choices": [
      {
        "message": {
          "content": "The Health and Safety at Work Act 1974..."
        }
      }
    ]
  },
  "status": "COMPLETED"
}
```

---

## Step 5: Configure Environment Variables

Update `.env` with all endpoint URLs:

```bash
# RunPod API Configuration
export RUNPOD_API_KEY="runpod-YOUR-KEY-HERE"

# Model Endpoints (replace {endpoint_id} with actual IDs)
export RUNPOD_ENDPOINT_LLAMA_70B="https://api.runpod.ai/v2/{llama70b_id}/runsync"
export RUNPOD_ENDPOINT_QWEN_72B="https://api.runpod.ai/v2/{qwen72b_id}/runsync"
export RUNPOD_ENDPOINT_LLAMA_8B="https://api.runpod.ai/v2/{llama8b_id}/runsync"
```

**Reload environment**:
```bash
source .env
```

---

## Step 6: Verify Setup

Check that all environment variables are set:

```bash
echo "API Key: ${RUNPOD_API_KEY:0:15}..."
echo "Llama 70B: $RUNPOD_ENDPOINT_LLAMA_70B"
echo "Qwen 72B: $RUNPOD_ENDPOINT_QWEN_72B"
echo "Llama 8B: $RUNPOD_ENDPOINT_LLAMA_8B"
```

---

## Step 7: Run Evaluation

### Create Test Dataset
```bash
mix evaluate.create_test_dataset
```

Expected output:
```
Creating test dataset for AI model evaluation...
Target size: 20 cases
Selected 20 unique cases
✓ Test dataset created: test/fixtures/ai_evaluation/test_dataset.json
```

### Quick Screening (5 cases, fast)
```bash
mix evaluate.ai_models --quick
```

### Full Evaluation (20 cases)
```bash
mix evaluate.ai_models
```

### Evaluate Single Model
```bash
mix evaluate.ai_models --model llama-3.1-70b
```

---

## Step 8: Review Results

Results are saved to `test/fixtures/ai_evaluation/results/`:

1. **`{model}_results.json`**: Raw enrichment outputs for each case
2. **`{model}_metrics.json`**: Performance statistics
3. **`comparison_report.md`**: Summary table and recommendations

### Review Checklist

- [ ] Check success rate (target: >95%)
- [ ] Review latency (target: <30s p95)
- [ ] Validate regulation links manually (sample 5 cases)
- [ ] Read summaries for quality and accuracy
- [ ] Check auto-tags for relevance
- [ ] Compare costs (calculate: tokens × model rate)

---

## Cost Optimization Tips

### 1. Use Serverless (Not Pod Rentals)
- **Serverless**: Pay only for execution time (~seconds per case)
- **Pod rental**: Pay 24/7 even when idle (not suitable for evaluation)

### 2. Start with Smallest Models
- Test Llama 8B first (cheapest)
- Only test larger models if quality insufficient

### 3. Use Quick Mode First
```bash
mix evaluate.ai_models --quick  # Only 5 cases
```

### 4. Set Idle Timeout Low
- Configure endpoints with 60-second idle timeout
- Prevents charges when not actively evaluating

### 5. Monitor Spend
- RunPod dashboard shows real-time costs
- Set budget alerts in RunPod settings

---

## Troubleshooting

### "Endpoint not found" Error
**Cause**: Incorrect endpoint URL or endpoint not deployed
**Fix**:
1. Check RunPod dashboard - endpoint status should be "Running"
2. Verify endpoint URL matches environment variable
3. Ensure endpoint ID is correct in URL

### Timeout Errors
**Cause**: Model cold start (first request) or complex input
**Fix**:
1. Increase timeout in evaluation script (currently 60s)
2. Use `/run` endpoint instead of `/runsync` for async
3. Reduce input prompt length

### "Insufficient credits" Error
**Cause**: RunPod account balance too low
**Fix**: Add credits via RunPod dashboard (minimum $10 recommended for eval)

### JSON Parsing Errors
**Cause**: Model didn't return valid JSON
**Fix**:
1. Check system prompt enforces JSON format
2. Add `"response_format": {"type": "json_object"}` to request
3. Use larger model (better instruction following)

---

## Expected Costs

### Evaluation Budget Estimate

**Assumptions**:
- 20 test cases
- ~1000 tokens input per case (case details + prompt)
- ~1500 tokens output per case (enrichment JSON)
- 3 models tested

**Estimated Costs**:

| Model | Cost/1k Tokens | Total Tokens | Est. Cost |
|-------|----------------|--------------|-----------|
| Llama 3.1 70B | $0.70 | 50k (20 × 2.5k) | $35.00 |
| Qwen 2.5 72B | $0.50 | 50k | $25.00 |
| Llama 3.1 8B | $0.08 | 50k | $4.00 |
| **Total** | | | **$64.00** |

**Recommended starting budget**: $100 (includes buffer for re-runs, debugging)

---

## Next Steps After Evaluation

1. **Select Production Model**: Choose based on accuracy/cost/speed balance
2. **Optimize Prompts**: Refine prompts for selected model
3. **Implement Production Service**: Create `EhsEnforcement.AI.EnrichmentService`
4. **Set Up Monitoring**: Track costs, latency, accuracy over time
5. **Create Feedback Loop**: Use `EnrichmentValidation` to improve prompts

---

## Production Deployment Considerations

### When to Use Serverless vs Dedicated Pods

**Serverless (Recommended for <1000 cases/month)**:
- ✅ Auto-scaling
- ✅ Pay per execution
- ✅ No idle costs
- ❌ Cold start latency (~5-10s)

**Dedicated Pods (For >5000 cases/month)**:
- ✅ No cold starts
- ✅ Predictable latency
- ✅ Volume discounts
- ❌ Pay 24/7 even when idle

**Recommendation**: Start with serverless, migrate to dedicated pods if volume increases.

---

## Alternative: OpenRouter.ai

If RunPod proves too expensive or complex, consider OpenRouter.ai:

**Pros**:
- Simple REST API (OpenAI-compatible)
- Multiple model providers (Claude, GPT-4, Llama, etc.)
- No infrastructure management
- Unified billing

**Cons**:
- Slightly higher per-token costs
- Less control over model hosting

**Setup**:
1. Sign up at https://openrouter.ai
2. Generate API key
3. Use OpenAI client library with custom base URL

---

**Document Status**: Setup Guide v1.0
**Last Updated**: 2025-11-22
**Next Review**: After initial model evaluation
