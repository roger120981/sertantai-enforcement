# RunPod Setup: Llama 3.1 8B Instruct

Setup guide for deploying Meta Llama 3.1 8B Instruct on RunPod for AI evaluation and development.

## Model Overview

| Property | Value |
|----------|-------|
| Model | `meta-llama/Meta-Llama-3.1-8B-Instruct` |
| Parameters | 8 billion |
| VRAM Required | ~16GB (FP16) |
| Use Case | Fast inference, cost-effective, good for structured output |
| Evaluation Role | Speed baseline, budget option |

## Recommended Configuration

### GPU Selection

| GPU | VRAM | Approx Cost/hr | Recommendation |
|-----|------|----------------|----------------|
| RTX 4090 | 24GB | ~$0.44 | Best value |
| RTX 3090 | 24GB | ~$0.30 | Budget option |
| A10 | 24GB | ~$0.50 | Alternative |

### Pod Settings

- **Volume Disk**: 50GB minimum
- **Container Disk**: 20GB (default is fine)
- **GPU Count**: 1

## Template Options

### Option 1: vLLM (Recommended)

Best for OpenAI-compatible API, fast inference.

1. **Template**: Search for `RunPod vLLM` or `vllm/vllm-openai`
2. **Environment Variables**:
   ```
   MODEL_NAME=meta-llama/Meta-Llama-3.1-8B-Instruct
   MAX_MODEL_LEN=8192
   ```
3. **Exposed Port**: 8000
4. **Endpoint Format**: 
   ```
   https://{POD_ID}-8000.proxy.runpod.net/v1/chat/completions
   ```

### Option 2: Ollama

Simpler setup, slightly slower.

1. **Template**: Search for `RunPod Ollama` or `ollama/ollama`
2. **After Deploy** (SSH in):
   ```bash
   ollama pull llama3.1:8b-instruct-fp16
   ```
3. **Exposed Port**: 11434
4. **Endpoint Format**:
   ```
   https://{POD_ID}-11434.proxy.runpod.net/v1/chat/completions
   ```

### Option 3: Text Generation Inference (TGI)

HuggingFace's inference server.

1. **Template**: Search for `Text Generation Inference`
2. **Environment Variables**:
   ```
   MODEL_ID=meta-llama/Meta-Llama-3.1-8B-Instruct
   MAX_INPUT_LENGTH=4096
   MAX_TOTAL_TOKENS=8192
   ```
3. **Exposed Port**: 80
4. **Endpoint Format**:
   ```
   https://{POD_ID}-80.proxy.runpod.net/v1/chat/completions
   ```

## Environment Variables for Evaluation

After pod is running, set in your local environment:

```bash
export RUNPOD_API_KEY="your-api-key"
export RUNPOD_ENDPOINT_LLAMA_8B="https://{POD_ID}-8000.proxy.runpod.net/v1/chat/completions"
```

## Verification

Test the endpoint is working:

```bash
curl -X POST "$RUNPOD_ENDPOINT_LLAMA_8B" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -d '{
    "model": "meta-llama/Meta-Llama-3.1-8B-Instruct",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'
```

## Expected Performance

| Metric | Expected Value |
|--------|----------------|
| Tokens/sec | 30-50 |
| Time per enrichment | 5-15 seconds |
| Cost per enrichment | ~$0.002 |

## Troubleshooting

### "No space left on device"
- Redeploy with larger volume disk (50GB+)

### Connection refused
- Check pod is running (not just starting)
- Verify port is exposed in RunPod dashboard
- Wait 2-3 minutes for model to load

### 401 Unauthorized
- Check `RUNPOD_API_KEY` is set correctly
- Verify API key in RunPod account settings

### Slow responses
- Model may still be loading (first request is slow)
- Check GPU utilization in pod logs

## Cost Estimate

For full evaluation (20 cases, ~10 min):
- RTX 4090: ~$0.08
- RTX 3090: ~$0.05

For production (~100 cases/month):
- ~$0.20/month (using on-demand pods)
- Consider serverless endpoint for production
