# RunPod Setup: Qwen 2.5 72B Instruct

Setup guide for deploying Qwen 2.5 72B Instruct on RunPod for AI evaluation and development.

## Model Overview

| Property | Value |
|----------|-------|
| Model | `Qwen/Qwen2.5-72B-Instruct` |
| Parameters | 72 billion |
| VRAM Required | ~144GB (FP16) or ~40GB (4-bit quantized) |
| Use Case | Strong reasoning, excellent instruction following, multilingual |
| Evaluation Role | Balanced accuracy/speed, production candidate |

## Why Qwen 2.5 72B?

- **No license restrictions** - Unlike Llama, no HuggingFace token needed
- **Strong structured output** - Excellent at following JSON schemas
- **Legal terminology** - Good performance on regulatory/compliance text
- **Competitive quality** - Benchmarks similar to Llama 3.1 70B

## Recommended Configuration

### GPU Selection

#### Full Precision (FP16) - Best Quality

| GPU Config | Total VRAM | Approx Cost/hr | Recommendation |
|------------|------------|----------------|----------------|
| 2x A100 80GB | 160GB | ~$3.20 | Best quality |
| 4x A6000 48GB | 192GB | ~$2.00 | Good alternative |
| 2x A100 40GB | 80GB | ~$2.40 | May need quantization |

#### Quantized (AWQ 4-bit) - Cost Effective

| GPU Config | Total VRAM | Approx Cost/hr | Recommendation |
|------------|------------|----------------|----------------|
| 2x RTX 4090 | 48GB | ~$0.88 | Best value for eval |
| 1x A100 80GB | 80GB | ~$1.60 | Single GPU option |
| 2x RTX 3090 | 48GB | ~$0.60 | Budget option |

### Pod Settings

- **Volume Disk**: 200GB minimum (model is ~145GB)
- **Container Disk**: 20GB (default is fine)
- **GPU Count**: 2 (for most configurations)

## Template Options

### Option 1: vLLM with Tensor Parallelism (Recommended)

Best for multi-GPU deployment.

1. **Template**: Search for `RunPod vLLM` or `vllm/vllm-openai`
2. **Environment Variables**:
   ```
   MODEL_NAME=Qwen/Qwen2.5-72B-Instruct
   TENSOR_PARALLEL_SIZE=2
   MAX_MODEL_LEN=32768
   GPU_MEMORY_UTILIZATION=0.95
   ```
3. **Exposed Port**: 8000
4. **Endpoint Format**: 
   ```
   https://{POD_ID}-8000.proxy.runpod.net/v1/chat/completions
   ```

**Note**: Qwen 2.5 supports 128K context, but 32K is sufficient for our use case.

### Option 2: vLLM with AWQ Quantization (Cost Effective)

Use 4-bit quantized model on smaller GPUs.

1. **Template**: Search for `RunPod vLLM`
2. **Environment Variables**:
   ```
   MODEL_NAME=Qwen/Qwen2.5-72B-Instruct-AWQ
   TENSOR_PARALLEL_SIZE=2
   MAX_MODEL_LEN=16384
   QUANTIZATION=awq
   ```
3. **Exposed Port**: 8000
4. **Endpoint Format**:
   ```
   https://{POD_ID}-8000.proxy.runpod.net/v1/chat/completions
   ```

### Option 3: Text Generation Inference (TGI)

HuggingFace's server with automatic sharding.

1. **Template**: Search for `Text Generation Inference`
2. **Environment Variables**:
   ```
   MODEL_ID=Qwen/Qwen2.5-72B-Instruct
   NUM_SHARD=2
   MAX_INPUT_LENGTH=8192
   MAX_TOTAL_TOKENS=16384
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
export RUNPOD_ENDPOINT_QWEN_72B="https://{POD_ID}-8000.proxy.runpod.net/v1/chat/completions"
```

## Verification

Test the endpoint is working:

```bash
curl -X POST "$RUNPOD_ENDPOINT_QWEN_72B" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -d '{
    "model": "Qwen/Qwen2.5-72B-Instruct",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'
```

## Expected Performance

| Configuration | Tokens/sec | Time per enrichment | Cost per enrichment |
|---------------|------------|---------------------|---------------------|
| 2x A100 80GB (FP16) | 15-25 | 15-30 seconds | ~$0.02 |
| 2x RTX 4090 (AWQ) | 12-22 | 18-35 seconds | ~$0.01 |
| 4x A6000 (FP16) | 12-20 | 20-35 seconds | ~$0.015 |

## Troubleshooting

### "CUDA out of memory"
- Use quantized model (AWQ)
- Reduce `MAX_MODEL_LEN` to 8192
- Increase `TENSOR_PARALLEL_SIZE` if more GPUs available

### "No space left on device"
- Redeploy with larger volume disk (200GB+)
- Model download is ~145GB

### Slow model loading
- 72B models take 5-10 minutes to load
- First request will be slow, subsequent requests faster
- Check pod logs for loading progress

### Connection timeout
- Increase client timeout to 120 seconds
- Model may still be loading

### JSON output issues
- Qwen excels at structured output
- If JSON is malformed, check temperature (use 0.1-0.3)
- Ensure `response_format: {"type": "json_object"}` is set

## Qwen vs Llama Comparison

| Aspect | Qwen 2.5 72B | Llama 3.1 70B |
|--------|--------------|---------------|
| License | Apache 2.0 (open) | Meta License (restricted) |
| HF Token Required | No | Yes |
| Context Length | 128K | 128K |
| Structured Output | Excellent | Very Good |
| Legal/Regulatory | Very Good | Very Good |
| Speed (similar hardware) | Similar | Similar |

For our use case (UK EHS enforcement enrichment), both are excellent candidates. Qwen's open license and strong structured output make it slightly preferable.

## Cost Estimate

For full evaluation (20 cases, ~30 min):
- 2x A100 80GB: ~$1.60
- 2x RTX 4090 (AWQ): ~$0.45

For production (~100 cases/month):
- ~$2-5/month (using on-demand pods)
- Serverless endpoint recommended for production

## Quantization Trade-offs

| Precision | Quality | Speed | VRAM | Recommendation |
|-----------|---------|-------|------|----------------|
| FP16 | 100% | Baseline | 144GB | Best accuracy |
| AWQ 4-bit | ~98% | Similar | 40GB | Best value |
| GPTQ 4-bit | ~97% | Faster | 40GB | Speed priority |

For enforcement enrichment (accuracy matters), AWQ 4-bit is the sweet spot.

## Special Features

### Long Context
Qwen 2.5 excels at long documents. For cases with extensive breach descriptions:
```
MAX_MODEL_LEN=65536
```

### System Prompt Optimization
Qwen responds well to structured system prompts:
```
You are an expert. Follow these rules:
1. Rule one
2. Rule two

Output format: JSON
```
