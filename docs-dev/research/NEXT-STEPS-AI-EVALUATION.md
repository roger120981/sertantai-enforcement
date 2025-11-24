# Next Steps: AI Model Evaluation

**Status**: Ready to execute evaluation
**Created**: 2025-11-22
**Estimated Time**: 4-6 hours (including RunPod setup)
**Budget**: £100 (~$130 USD)

---

## Quick Summary

You now have a complete evaluation framework ready to test AI models on RunPod for enforcement case enrichment. Here's what to do next:

---

## Immediate Action Items

### 1. Add HTTP Client Dependency ⏱️ 2 minutes

```bash
cd /home/jason/Desktop/sertantai-enforcement
```

Edit `mix.exs` and add to the `deps` function:
```elixir
{:httpoison, "~> 2.2"}
```

Then run:
```bash
mix deps.get
```

---

### 2. Set Up RunPod Account ⏱️ 15-20 minutes

Follow the detailed guide: `docs-dev/research/runpod-setup-guide.md`

**Quick checklist**:
- [ ] Create RunPod.io account
- [ ] Add credit card (minimum $50 recommended)
- [ ] Generate API key
- [ ] Create 3 serverless endpoints:
  - Llama 3.1 70B Instruct
  - Qwen 2.5 72B Instruct
  - Llama 3.1 8B Instruct
- [ ] Copy endpoint URLs

---

### 3. Configure Environment Variables ⏱️ 5 minutes

Create/update `.env` file:
```bash
# RunPod API Configuration
export RUNPOD_API_KEY="runpod-YOUR-KEY-HERE"

# Model Endpoints
export RUNPOD_ENDPOINT_LLAMA_70B="https://api.runpod.ai/v2/{endpoint_id}/runsync"
export RUNPOD_ENDPOINT_QWEN_72B="https://api.runpod.ai/v2/{endpoint_id}/runsync"
export RUNPOD_ENDPOINT_LLAMA_8B="https://api.runpod.ai/v2/{endpoint_id}/runsync"
```

Load environment:
```bash
source .env
```

Verify:
```bash
echo "API Key: ${RUNPOD_API_KEY:0:15}..."
```

---

### 4. Create Test Dataset ⏱️ 1 minute

```bash
mix evaluate.create_test_dataset
```

Expected output:
```
Creating test dataset for AI model evaluation...
Target size: 20 cases
Selected 20 unique cases
✓ Test dataset created: test/fixtures/ai_evaluation/test_dataset.json

Dataset Summary:
================
Temporal Distribution:
  0-3 months: 3 cases
  3-6 months: 0 cases
  6-12 months: 3 cases
  12+ months: 2 cases

Fine Range Distribution:
  <£10k: 3 cases
  £10k-£100k: 3 cases
  >£100k: 3 cases
  No fine: 0 cases
```

---

### 5. Run Quick Screening ⏱️ 5-10 minutes

Test with just 5 cases to verify setup:

```bash
mix evaluate.ai_models --quick
```

This will:
- Test all 3 configured models
- Process only 5 cases (fast, cheap)
- Generate initial metrics
- Verify API connectivity

**Expected cost**: ~$5-10

---

### 6. Review Quick Results ⏱️ 10 minutes

Check generated files in `test/fixtures/ai_evaluation/results/`:

```bash
ls -lh test/fixtures/ai_evaluation/results/

# View comparison report
cat test/fixtures/ai_evaluation/results/comparison_report.md

# Check a sample enrichment
cat test/fixtures/ai_evaluation/results/llama-3.1-8b_results.json | jq '.enrichments[0]'
```

**Decision point**: If quick screening looks good, proceed to full evaluation.

---

### 7. Run Full Evaluation ⏱️ 30-60 minutes

```bash
mix evaluate.ai_models
```

This will:
- Process all 20 test cases
- Test all 3 models
- Generate comprehensive metrics
- Create comparison report

**Expected cost**: ~$50-70

---

### 8. Manual Quality Review ⏱️ 2-3 hours

**Critical step**: Automated metrics don't catch everything!

For each model, manually review **5 sample cases**:

#### A. Regulation Links Accuracy
- [ ] Are primary regulations correct?
- [ ] Are section citations accurate?
- [ ] Are related regulations relevant?

#### B. Benchmark Analysis Validity
- [ ] Does fine percentile make sense?
- [ ] Are similar cases counts reasonable?
- [ ] Is severity assessment accurate?

#### C. Pattern Detection Relevance
- [ ] Is industry pattern accurate?
- [ ] Is recurring violation theme valid?
- [ ] Are similar case suggestions helpful?

#### D. Summary Quality
- [ ] **Layperson summary**: Clear, accurate, appropriate length?
- [ ] **Professional summary**: Technically precise, legally sound?

#### E. Tag Accuracy
- [ ] All relevant tags present?
- [ ] No irrelevant tags?
- [ ] Useful for filtering/search?

**Scoring**: Use the framework rubric (docs-dev/research/ai-model-evaluation-framework.md, Section 5)

---

### 9. Cost Calculation ⏱️ 15 minutes

Calculate actual cost per enrichment:

```bash
# Check RunPod dashboard for actual spend
# Divide by number of enrichments

# Example:
# Total spend: $64
# Total enrichments: 60 (20 cases × 3 models)
# Cost per enrichment: $1.07

# For production (1000 cases/month):
# Monthly cost estimate: 1000 × $1.07 = $1,070/month
```

**Target**: <£0.50 (~$0.65) per case
**Acceptable**: <£1.00 (~$1.30) per case

---

### 10. Select Production Model ⏱️ 30 minutes

Compare models across 4 dimensions:

| Dimension | Weight | Evaluation Method |
|-----------|--------|-------------------|
| **Accuracy** | 60% | Manual review scores |
| **Speed** | 20% | P95 latency metric |
| **Cost** | 15% | $/case calculation |
| **Reliability** | 5% | Success rate % |

**Decision matrix**:
```
If accuracy_score > 85% AND cost < $1.00:
  → SELECT model
Else if accuracy_score > 80% AND cost < $0.50:
  → SELECT model (acceptable trade-off)
Else:
  → REJECT, try different model or improve prompts
```

**Document decision** in session file with justification.

---

## Expected Timeline

| Phase | Time | Cost |
|-------|------|------|
| 1. Setup (deps, RunPod, env) | 30 min | $0 |
| 2. Create test dataset | 1 min | $0 |
| 3. Quick screening | 10 min | $10 |
| 4. Full evaluation | 60 min | $60 |
| 5. Manual quality review | 180 min | $0 |
| 6. Cost calculation | 15 min | $0 |
| 7. Decision & documentation | 30 min | $0 |
| **Total** | **~5 hours** | **~$70** |

---

## Evaluation Outputs

After completing evaluation, you will have:

### 1. Quantitative Metrics
- Success rates (%)
- Latency statistics (ms)
- Throughput (cases/hour)
- Cost per enrichment ($)

### 2. Qualitative Scores
- Regulation accuracy (0-10 points)
- Benchmark validity (0-10 points)
- Pattern relevance (0-8 points)
- Summary quality (0-13 points)
- Tag accuracy (precision/recall)

### 3. Decision Artifacts
- Comparison report (markdown)
- Selected model with justification
- Optimized prompts for production
- Configuration recommendations

### 4. Production Readiness
- API endpoint configuration
- Environment variables
- Cost monitoring setup
- Error handling strategy

---

## If Evaluation Results Are Poor

### Scenario A: All Models Score <70%

**Likely causes**:
- Prompts need refinement
- Test dataset not representative
- Models need more context

**Actions**:
1. Review sample enrichments to identify common errors
2. Refine prompt engineering (add examples, clearer instructions)
3. Test larger models (Llama 3.1 405B if available)
4. Consider alternative approach (fine-tuned model, RAG system)

### Scenario B: Costs Exceed Budget (>£1/case)

**Likely causes**:
- Large models too expensive
- Prompts generating excessive tokens

**Actions**:
1. Switch to smaller model (Llama 8B)
2. Reduce output verbosity in prompts
3. Use OpenRouter.ai for better pricing
4. Consider batch processing discounts

### Scenario C: Latency Too High (>60s p95)

**Likely causes**:
- Model cold starts
- Large context windows

**Actions**:
1. Use dedicated pods (eliminates cold starts)
2. Reduce prompt length
3. Switch to faster model
4. Implement async processing (user doesn't wait)

---

## After Model Selection

Once you've selected a production model, proceed to:

1. **Implement AI Service** (`lib/ehs_enforcement/ai/enrichment_service.ex`)
   - Use winning model's API configuration
   - Port optimized prompts from evaluation
   - Add error handling and retry logic

2. **Create Oban Worker** (`lib/ehs_enforcement/workers/enrich_enforcement_action_worker.ex`)
   - Background job processing
   - Exponential backoff for failures
   - Telemetry events for monitoring

3. **Add Integration Hooks**
   - `after_action` on Case.create
   - `after_action` on Notice.create
   - Manual trigger UI in admin panel

4. **Production Testing**
   - Test with real new cases
   - Monitor costs in RunPod dashboard
   - Track accuracy via `EnrichmentValidation` feedback

---

## Useful Commands Reference

```bash
# Create test dataset
mix evaluate.create_test_dataset

# Quick screening (5 cases)
mix evaluate.ai_models --quick

# Full evaluation (20 cases)
mix evaluate.ai_models

# Evaluate single model
mix evaluate.ai_models --model llama-3.1-70b

# Check results
ls -lh test/fixtures/ai_evaluation/results/
cat test/fixtures/ai_evaluation/results/comparison_report.md

# Verify environment
echo $RUNPOD_API_KEY
echo $RUNPOD_ENDPOINT_LLAMA_70B
```

---

## Questions to Answer During Evaluation

1. **Which model provides best regulation identification?**
   - Track: Primary regulation accuracy, section citation correctness

2. **Which model generates most useful summaries?**
   - Layperson summary readability
   - Professional summary technical precision

3. **Is benchmark analysis accurate?**
   - Cross-check fine percentiles against database stats
   - Validate similar case counts

4. **Are auto-tags useful for search/filtering?**
   - Precision: No irrelevant tags
   - Recall: All important categories covered

5. **What's the cost-benefit sweet spot?**
   - Best accuracy at acceptable cost
   - Is 10% better accuracy worth 5x cost?

---

## Success Criteria

**Minimum Viable**:
- ✅ Success rate: >90%
- ✅ P95 latency: <60s
- ✅ Cost: <£1.50/case
- ✅ Regulation accuracy: >70%
- ✅ Summary quality: >75%

**Target**:
- ✅ Success rate: >98%
- ✅ P95 latency: <30s
- ✅ Cost: <£0.50/case
- ✅ Regulation accuracy: >85%
- ✅ Summary quality: >85%

---

## Resources

- **Evaluation Framework**: `docs-dev/research/ai-model-evaluation-framework.md`
- **RunPod Setup**: `docs-dev/research/runpod-setup-guide.md`
- **Session Log**: `.claude/sessions/2025-11-20-Github-Issue-2.md`
- **GitHub Issue**: https://github.com/shotleybuilder/sertantai-enforcement/issues/2

---

**Ready to proceed?** Start with Step 1: Add HTTPoison dependency! 🚀
