# RunPod Setup: Llama 3.1 70B Instruct

Setup guide for deploying Meta Llama 3.1 70B Instruct on RunPod for AI evaluation and development.

## Model Overview

| Property | Value |
|----------|-------|
| Model | `meta-llama/Meta-Llama-3.1-70B-Instruct` |
| Parameters | 70 billion |
| VRAM Required | ~140GB (FP16) or ~40GB (4-bit quantized) |
| Use Case | High accuracy, complex reasoning, legal/regulatory analysis |
| Evaluation Role | Accuracy baseline, production candidate |

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

- **Volume Disk**: 200GB minimum (model is ~140GB)
- **Container Disk**: 20GB (default is fine)
- **GPU Count**: 2 (for most configurations)

## Template Options

### Option 1: vLLM with Tensor Parallelism (Recommended)

Best for multi-GPU deployment.

1. **Template**: Search for `RunPod vLLM` or `vllm/vllm-openai`
2. **Environment Variables**:
   ```
   MODEL_NAME=meta-llama/Meta-Llama-3.1-70B-Instruct
   TENSOR_PARALLEL_SIZE=2
   MAX_MODEL_LEN=8192
   GPU_MEMORY_UTILIZATION=0.95
   ```
3. **Exposed Port**: 8000
4. **Endpoint Format**: 
   ```
   https://{POD_ID}-8000.proxy.runpod.net/v1/chat/completions
   ```

### Option 2: vLLM with AWQ Quantization (Cost Effective)

Use 4-bit quantized model on smaller GPUs.

1. **Template**: Search for `RunPod vLLM`
2. **Environment Variables**:
   ```
   MODEL_NAME=hugging-quants/Meta-Llama-3.1-70B-Instruct-AWQ-INT4
   TENSOR_PARALLEL_SIZE=2
   MAX_MODEL_LEN=8192
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
   MODEL_ID=meta-llama/Meta-Llama-3.1-70B-Instruct
   NUM_SHARD=2
   MAX_INPUT_LENGTH=4096
   MAX_TOTAL_TOKENS=8192
   QUANTIZE=bitsandbytes-nf4
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
export RUNPOD_ENDPOINT_LLAMA_70B="https://{POD_ID}-8000.proxy.runpod.net/v1/chat/completions"
```

## Verification

Test the endpoint is working:

```bash
curl -X POST "$RUNPOD_ENDPOINT_LLAMA_70B" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -d '{
    "model": "meta-llama/Meta-Llama-3.1-70B-Instruct",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 50
  }'
```

## Expected Performance

| Configuration | Tokens/sec | Time per enrichment | Cost per enrichment |
|---------------|------------|---------------------|---------------------|
| 2x A100 80GB (FP16) | 15-25 | 15-30 seconds | ~$0.02 |
| 2x RTX 4090 (AWQ) | 10-20 | 20-40 seconds | ~$0.01 |
| 4x A6000 (FP16) | 12-20 | 20-35 seconds | ~$0.015 |

## Troubleshooting

### "CUDA out of memory"
- Use quantized model (AWQ/GPTQ)
- Reduce `MAX_MODEL_LEN` to 4096
- Increase `TENSOR_PARALLEL_SIZE` if more GPUs available

### "No space left on device"
- Redeploy with larger volume disk (200GB+)
- Model download is ~140GB

### Slow model loading
- 70B models take 5-10 minutes to load
- First request will be slow, subsequent requests faster
- Check pod logs for loading progress

### Connection timeout
- Increase client timeout to 120 seconds
- Model may still be loading

### "Model not found"
- Check HuggingFace access token if model is gated
- Add `HUGGING_FACE_HUB_TOKEN` environment variable

## HuggingFace Access Token

Llama 3.1 70B requires accepting Meta's license:

1. Go to https://huggingface.co/meta-llama/Meta-Llama-3.1-70B-Instruct
2. Accept the license agreement
3. Create access token at https://huggingface.co/settings/tokens
4. Add to pod environment:
   ```
   HUGGING_FACE_HUB_TOKEN=hf_xxxxx
   ```

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
| FP16 | 100% | Baseline | 140GB | Best accuracy |
| AWQ 4-bit | ~98% | Similar | 40GB | Best value |
| GPTQ 4-bit | ~97% | Faster | 40GB | Speed priority |
| bitsandbytes NF4 | ~96% | Slower | 40GB | Easy setup |

For enforcement enrichment (accuracy matters), AWQ 4-bit is the sweet spot.
