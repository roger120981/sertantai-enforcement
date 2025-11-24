# AI Model Evaluation Framework for Enforcement Enrichment

**Created**: 2025-11-22
**Purpose**: Evaluate RunPod AI models for case/notice enrichment task
**Context**: GitHub Issue #2 - AI Context Generation

---

## Executive Summary

This framework provides a systematic approach to evaluating AI models on RunPod.io for enriching UK environmental, health, and safety enforcement data. The evaluation focuses on practical performance with low-volume, forward-looking enrichment tasks.

---

## 1. Business Context

### Data Volume Profile
- **Current Dataset**: 6,288 enforcement cases
- **Monthly Ingestion Rate**: ~50-100 new cases/notices (estimated)
- **Enrichment Strategy**: Primarily forward-looking (enrich new cases as they arrive)
- **Historical Enrichment**: Limited value for cases >2 years old

### Cost-Benefit Analysis
- **Forward enrichment**: High value (helps professionals analyze current trends)
- **Recent history (6-12 months)**: Medium value (pattern detection, benchmarking)
- **Deep history (>2 years)**: Low value (regulatory landscape changes over time)

### Performance Requirements
- **Latency**: <30 seconds per case (background job acceptable)
- **Accuracy**: High priority (legal/compliance context)
- **Cost**: Secondary concern (low volume = low total cost)
- **Reliability**: Must handle API failures gracefully

---

## 2. Enrichment Tasks

Each case/notice will be enriched with the following AI-generated fields:

### A. Regulation Links (JSONB)
**Purpose**: Map violations to specific UK EHS regulations
**Expected Output**:
```json
{
  "primary_regulations": [
    {
      "title": "Health and Safety at Work Act 1974",
      "section": "Section 2(1)",
      "relevance": "Employer duty of care violation"
    }
  ],
  "related_regulations": [...]
}
```

### B. Benchmark Analysis (JSONB)
**Purpose**: Compare fine/penalty against similar cases
**Expected Output**:
```json
{
  "fine_percentile": 75,
  "similar_cases_count": 23,
  "average_fine_similar": 45000,
  "severity_assessment": "above average penalty"
}
```

### C. Pattern Detection (JSONB)
**Purpose**: Identify recurring issues, industry patterns
**Expected Output**:
```json
{
  "industry_pattern": "construction sector fall from height",
  "recurring_violation": "inadequate scaffolding inspection",
  "similar_case_ids": ["uuid1", "uuid2"]
}
```

### D. Layperson Summary (TEXT)
**Purpose**: Plain English explanation for non-experts
**Expected Length**: 150-300 words
**Tone**: Accessible, educational

### E. Professional Summary (TEXT)
**Purpose**: Technical analysis for compliance professionals
**Expected Length**: 200-400 words
**Tone**: Technical, legal precision

### F. Auto-Tags (JSONB Array)
**Purpose**: Categorization for filtering/search
**Expected Output**:
```json
["workplace_safety", "construction", "fatal_injury", "section_2_breach"]
```

### G. Confidence Scores (JSONB)
**Purpose**: Model confidence for each enrichment type
**Expected Output**:
```json
{
  "regulation_links": 0.92,
  "benchmark_analysis": 0.78,
  "pattern_detection": 0.65,
  "summaries": 0.88,
  "tags": 0.91
}
```

---

## 3. Test Dataset Selection

### Sample Size
- **Minimum**: 10 cases (5 recent, 5 varied complexity)
- **Recommended**: 20 cases (diverse scenarios)
- **Maximum**: 50 cases (comprehensive evaluation)

### Selection Criteria

#### A. Temporal Distribution (5 cases)
- 2 cases from last 3 months
- 2 cases from 6-12 months ago
- 1 case from 1-2 years ago

#### B. Financial Range (5 cases)
- 2 low fines (<£10,000)
- 2 medium fines (£10,000-£100,000)
- 1 high fine (>£100,000)

#### C. Complexity Levels (5 cases)
- 2 simple cases (single violation, clear outcome)
- 2 moderate cases (multiple violations, standard regulatory action)
- 1 complex case (multi-violation, environmental impact, high penalty)

#### D. Industry Diversity (5 cases)
- Construction
- Manufacturing
- Waste management
- Utilities/infrastructure
- Other sectors

### SQL Query for Test Dataset
```sql
-- Create balanced test dataset
WITH recent_cases AS (
  SELECT id, offence_fine, offence_result, inserted_at
  FROM cases
  WHERE inserted_at >= NOW() - INTERVAL '3 months'
  ORDER BY RANDOM()
  LIMIT 2
),
medium_age_cases AS (
  SELECT id, offence_fine, offence_result, inserted_at
  FROM cases
  WHERE inserted_at BETWEEN NOW() - INTERVAL '12 months' AND NOW() - INTERVAL '6 months'
  ORDER BY RANDOM()
  LIMIT 2
),
older_cases AS (
  SELECT id, offence_fine, offence_result, inserted_at
  FROM cases
  WHERE inserted_at BETWEEN NOW() - INTERVAL '24 months' AND NOW() - INTERVAL '12 months'
  ORDER BY RANDOM()
  LIMIT 1
),
low_fine_cases AS (
  SELECT id, offence_fine, offence_result, inserted_at
  FROM cases
  WHERE offence_fine < 10000
  ORDER BY RANDOM()
  LIMIT 2
),
medium_fine_cases AS (
  SELECT id, offence_fine, offence_result, inserted_at
  FROM cases
  WHERE offence_fine BETWEEN 10000 AND 100000
  ORDER BY RANDOM()
  LIMIT 2
),
high_fine_cases AS (
  SELECT id, offence_fine, offence_result, inserted_at
  FROM cases
  WHERE offence_fine > 100000
  ORDER BY RANDOM()
  LIMIT 1
)
SELECT DISTINCT id, offence_fine, offence_result, inserted_at
FROM (
  SELECT * FROM recent_cases
  UNION ALL SELECT * FROM medium_age_cases
  UNION ALL SELECT * FROM older_cases
  UNION ALL SELECT * FROM low_fine_cases
  UNION ALL SELECT * FROM medium_fine_cases
  UNION ALL SELECT * FROM high_fine_cases
) combined
LIMIT 20;
```

---

## 4. RunPod Model Candidates

### Recommended Models to Test

#### Tier 1: High-Performance (Best Accuracy)
1. **Meta Llama 3.1 70B Instruct**
   - Strong reasoning capabilities
   - Good for complex legal/regulatory analysis
   - Higher cost, slower inference

2. **Qwen 2.5 72B Instruct**
   - Excellent instruction following
   - Strong multilingual capabilities (handles legal terminology)
   - Competitive pricing

#### Tier 2: Balanced (Cost/Performance)
3. **Meta Llama 3.1 8B Instruct**
   - Fast inference
   - Good for structured tasks (tagging, categorization)
   - Lower cost

4. **Mistral 7B Instruct**
   - Efficient performance
   - Strong JSON output formatting
   - Very cost-effective

#### Tier 3: Specialized (If Available)
5. **Mixtral 8x7B**
   - Mixture of experts architecture
   - Good for diverse task handling
   - Balance of speed and quality

### Model Selection Criteria
- **JSON Output Support**: Critical for JSONB fields
- **Context Window**: Must handle case details + regulations (8k+ tokens)
- **Legal/Regulatory Knowledge**: Pre-training on legal texts preferred
- **API Availability**: REST API or OpenAI-compatible endpoint

---

## 5. Evaluation Metrics

### A. Accuracy Metrics

#### 1. Regulation Identification Accuracy
- **Manual Review**: Expert validates regulation references
- **Scoring**:
  - Correct primary regulation: 3 points
  - Correct section citation: 2 points
  - Relevant related regulations: 1 point each
- **Target Score**: >80% (8/10 points average)

#### 2. Benchmark Analysis Accuracy
- **Validation**: Cross-check against database statistics
- **Metrics**:
  - Fine percentile calculation accuracy (±10% tolerance)
  - Similar cases count accuracy (±20% tolerance)
- **Target**: >75% within tolerance

#### 3. Pattern Detection Relevance
- **Manual Review**: Expert assesses pattern validity
- **Scoring**:
  - Relevant industry pattern: 3 points
  - Accurate violation recurring theme: 3 points
  - Valid similar case suggestions: 2 points
- **Target Score**: >70% (6/8 points average)

#### 4. Summary Quality
- **Layperson Summary**:
  - Readability (Flesch-Kincaid Grade Level 8-10): 2 points
  - Factual accuracy: 3 points
  - Appropriate length (150-300 words): 1 point
- **Professional Summary**:
  - Technical precision: 3 points
  - Legal accuracy: 3 points
  - Appropriate length (200-400 words): 1 point
- **Target Score**: >80% for each summary type

#### 5. Tag Accuracy
- **Validation**: Expert review of auto-generated tags
- **Metrics**:
  - Relevant tags: Count correct tags
  - Irrelevant tags: Count incorrect tags
  - Missing tags: Count omissions
- **Target**: Precision >85%, Recall >70%

### B. Performance Metrics

#### 1. Latency
- **Measurement**: End-to-end enrichment time per case
- **Target**: <30 seconds (p95)
- **Critical Threshold**: <60 seconds (p99)

#### 2. Throughput
- **Measurement**: Cases enriched per hour
- **Target**: >60 cases/hour (batch processing)

#### 3. Cost per Enrichment
- **Calculation**: (API cost + compute cost) / case
- **Target**: <£0.50 per case (£500/month for 1000 cases)
- **Acceptable**: <£1.00 per case

### C. Reliability Metrics

#### 1. Success Rate
- **Measurement**: % of successful enrichments without errors
- **Target**: >98%

#### 2. Confidence Calibration
- **Validation**: Compare confidence scores to actual accuracy
- **Method**: Bin predictions by confidence, measure accuracy per bin
- **Target**: Well-calibrated (high confidence = high accuracy)

#### 3. Error Handling
- **Test**: Malformed inputs, API failures, timeout scenarios
- **Requirement**: Graceful degradation (partial enrichment better than none)

---

## 6. Evaluation Process

### Phase 1: Initial Screening (1-2 hours per model)
1. **Setup**: Create RunPod pod with candidate model
2. **Test**: Run 5 representative cases through enrichment pipeline
3. **Quick Assessment**: Review quality of regulation links and summaries
4. **Decision**: Go/No-Go for full evaluation

### Phase 2: Comprehensive Evaluation (4-6 hours per model)
1. **Run Full Test Dataset**: Enrich all 20 test cases
2. **Automated Metrics**: Collect latency, cost, success rate data
3. **Manual Review**: Expert evaluates accuracy metrics
4. **Score Compilation**: Aggregate results into scorecard

### Phase 3: Head-to-Head Comparison (2 hours)
1. **Top 2-3 Models**: Compare best performers side-by-side
2. **Edge Case Testing**: Challenge with difficult cases
3. **Cost-Benefit Analysis**: Factor in ongoing operational costs
4. **Final Recommendation**: Select production model

---

## 7. Scoring Rubric

### Weighted Scoring System

| Metric                          | Weight | Target | Scoring Method          |
|---------------------------------|--------|--------|-------------------------|
| Regulation Identification       | 20%    | >80%   | Point system (0-10)     |
| Benchmark Analysis              | 15%    | >75%   | % within tolerance      |
| Pattern Detection               | 15%    | >70%   | Point system (0-8)      |
| Layperson Summary Quality       | 12%    | >80%   | Point system (0-6)      |
| Professional Summary Quality    | 13%    | >80%   | Point system (0-7)      |
| Tag Accuracy (Precision)        | 10%    | >85%   | Precision metric        |
| Latency (p95)                   | 8%     | <30s   | Inverse scoring         |
| Cost per Enrichment             | 5%     | <£0.50 | Inverse scoring         |
| Success Rate                    | 2%     | >98%   | Percentage              |

**Total Possible Score**: 100 points

### Interpretation
- **90-100**: Excellent - Production ready
- **75-89**: Good - Acceptable with minor tuning
- **60-74**: Fair - Needs prompt engineering
- **<60**: Poor - Consider alternative model

---

## 8. Implementation: Evaluation Script

### Tool: Mix Task for Elixir

Create `mix evaluate.ai_models` task that:
1. Loads test dataset from database
2. Calls RunPod API for each model
3. Stores enrichment outputs
4. Generates comparison report

### Pseudo-code Structure
```elixir
defmodule Mix.Tasks.Evaluate.AiModels do
  use Mix.Task

  @models [
    %{name: "llama-3.1-70b", endpoint: "..."},
    %{name: "qwen-2.5-72b", endpoint: "..."},
    %{name: "llama-3.1-8b", endpoint: "..."}
  ]

  def run(_args) do
    test_cases = load_test_dataset()

    Enum.each(@models, fn model ->
      results = enrich_cases(test_cases, model)
      save_results(model, results)
      generate_report(model, results)
    end)

    generate_comparison_report(@models)
  end
end
```

---

## 9. Ground Truth Dataset

### Creating Reference Enrichments

For **5 "golden" cases**, manually create expert-validated enrichments:

1. **Select Cases**: Pick 5 diverse cases from test dataset
2. **Expert Enrichment**: Compliance professional manually enriches these cases
3. **Gold Standard**: Store in `test/fixtures/golden_enrichments.json`
4. **Automated Comparison**: Use for quantitative accuracy scoring

### Golden Case Criteria
- Wide range of complexity (simple to complex)
- Different industries
- Various fine levels
- Clear, unambiguous regulation references
- Well-documented similar cases in database

---

## 10. Evaluation Outputs

### A. Per-Model Report
- **Summary Stats**: Accuracy, latency, cost, success rate
- **Sample Enrichments**: 3 best, 3 worst examples
- **Error Analysis**: Common failure modes
- **Recommendation**: Production readiness score

### B. Comparison Matrix
| Model           | Accuracy | Latency | Cost/Case | Overall Score |
|-----------------|----------|---------|-----------|---------------|
| Llama 3.1 70B   | 87%      | 22s     | £0.45     | 92/100        |
| Qwen 2.5 72B    | 85%      | 18s     | £0.38     | 88/100        |
| Llama 3.1 8B    | 78%      | 8s      | £0.12     | 82/100        |

### C. Decision Document
- **Winner**: Recommended model with justification
- **Backup**: Second choice if primary unavailable
- **Prompt Templates**: Optimized prompts for production use
- **Configuration**: API settings, retry logic, fallback strategy

---

## 11. Next Steps After Evaluation

### Immediate Actions
1. ✅ Review this framework with stakeholder
2. ⏭️ Create test dataset (run SQL query, export to JSON)
3. ⏭️ Set up RunPod account and API access
4. ⏭️ Implement evaluation Mix task
5. ⏭️ Run Phase 1 screening on 3-4 candidate models

### Week 1: Evaluation Execution
- Day 1-2: Setup infrastructure, create test dataset
- Day 3-4: Run evaluations on top 3 models
- Day 5: Expert review, generate reports, select winner

### Week 2: Integration
- Implement production AI service with selected model
- Add retry logic, error handling, fallback strategies
- Integrate with Oban worker
- Deploy to staging environment

---

## 12. Risk Mitigation

### Key Risks

#### A. Model Availability/Deprecation
- **Mitigation**: Evaluate 2-3 models, have backup ready
- **Monitoring**: Track RunPod model availability announcements

#### B. Cost Overruns
- **Mitigation**: Set monthly budget limits, monitor usage
- **Fallback**: Reduce enrichment frequency or switch to cheaper model

#### C. Accuracy Degradation Over Time
- **Mitigation**: Quarterly re-evaluation with new cases
- **Monitoring**: Track confidence scores and user validation feedback

#### D. API Reliability Issues
- **Mitigation**: Implement exponential backoff, circuit breaker pattern
- **Fallback**: Queue failed enrichments for retry, partial enrichment acceptable

---

## Appendix A: Prompt Engineering Templates

### Template 1: Regulation Links
```
You are a UK environmental, health, and safety compliance expert.
Analyze this enforcement case and identify the specific regulations violated.

Case Details:
- Offence Result: {offence_result}
- Offence Action Type: {offence_action_type}
- Fine: £{offence_fine}
- Description: {offence_breaches}

Task: Provide a JSON response with:
1. Primary regulations violated (title, section, relevance)
2. Related regulations (secondary references)

Output format (strict JSON):
{
  "primary_regulations": [...],
  "related_regulations": [...]
}
```

### Template 2: Benchmark Analysis
*(Similar structured prompts for each enrichment type)*

---

## Appendix B: Test Dataset Export Script

```bash
# Export test dataset to JSON for evaluation
psql -h localhost -p 5434 -U postgres -d ehs_enforcement_dev -c \
"COPY (
  SELECT row_to_json(t) FROM (
    SELECT id, case_reference, offence_result, offence_fine,
           offence_breaches, inserted_at
    FROM cases
    WHERE id IN ('uuid1', 'uuid2', ...)
  ) t
) TO '/tmp/test_dataset.json';"
```

---

**Document Status**: Draft v1.0
**Next Review**: After initial model evaluation
**Owner**: Development Team
