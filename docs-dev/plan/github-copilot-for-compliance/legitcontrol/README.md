# Legit Control SDK Integration

> **Vision**: Add enterprise-grade governance, auditability, and version control to AI-driven compliance workflows using [Legit Control](https://legitcontrol.com).

This directory explores how Legit Control's "write-enabled AI" infrastructure can enhance the EHS Enforcement platform's AI capabilities with immutable audit trails, branching workflows, and human-in-the-loop governance.

---

## What is Legit Control?

Legit Control provides **version control for AI actions** - think Git, but for every change an AI agent makes to your data. Key capabilities:

| Feature | Description |
|---------|-------------|
| **Audit Trails** | Immutable history of every AI action with timestamps and attribution |
| **Branching** | Isolate proposed changes for review before committing to production |
| **Reversibility** | Safely rollback any AI-driven change to a previous state |
| **Attribution** | Track which agent, model, or user made each change |
| **Compliance Reporting** | Generate proof of governance for regulatory requirements |

---

## Why Legit Control + EHS Enforcement?

Our platform already uses AI for:
- **Case/Notice Enrichment** - AI adds regulation links, summaries, benchmarks
- **NL Query Translation** - AI converts natural language to database filters
- **Risk Scoring** - AI calculates supplier pre-qualification scores
- **Predictive Analytics** - AI forecasts enforcement trends

**The Problem**: These AI actions modify data that may be used in legal proceedings, contract decisions, and regulatory compliance. We need:
1. **Proof** of what the AI did and why
2. **Human approval** before critical changes go live
3. **Rollback capability** if AI makes errors
4. **Audit trails** for regulatory inquiries

**Legit Control solves all of these.**

---

## Synergies with Current Features

### 1. AI Case Context Enrichment
**Current**: AI enriches enforcement cases with regulation links, benchmarks, summaries
**With Legit Control**:
- Every enrichment is a versioned "commit" with full attribution
- Professional validators can review AI suggestions in a "branch" before merging
- If AI misidentifies a regulation, rollback to previous version instantly
- Generate compliance reports showing AI enrichment → human validation chain

**Integration Point**: `EhsEnforcement.AI.EnrichmentService`

### 2. Contract Pre-Qualification Intelligence
**Current**: AI calculates risk scores for supplier pre-qualification
**With Legit Control**:
- Risk score calculations become auditable decisions
- Procurement teams can prove due diligence with immutable history
- If a supplier disputes their score, show exact data and reasoning
- Branch proposed score changes for manager approval

**Integration Point**: `EhsEnforcement.PreQualification.RiskCalculator`

### 3. Expert Commentary System
**Current**: Professionals add commentary with AI writing assistance
**With Legit Control**:
- Track AI suggestions vs human edits clearly
- Separate "AI-drafted" from "human-approved" content
- Version control for legal/compliance commentary
- Prove that final published commentary was human-reviewed

**Integration Point**: Expert commentary editor with AI assistance

### 4. Offender Breach Expansion
**Current**: Companies submit context about their enforcement actions
**With Legit Control**:
- AI-structured narratives are versioned separately from raw submissions
- Companies can see exactly what AI changed in their submission
- Audit trail proves original submission was not altered
- Branch for moderation review before publishing

**Integration Point**: `EhsEnforcement.Enforcement.OffenderResponse`

---

## Synergies with Future Features

### 5. AI Compliance Copilot
**Future**: ChatGPT-style assistant for compliance queries
**With Legit Control**:
- Log every AI response with context and sources
- Track which responses were used for business decisions
- Audit trail for "the AI told me to do X" scenarios
- Version conversation history for regulatory inquiries

### 6. Predictive Risk Intelligence
**Future**: ML-powered trend forecasting and risk alerts
**With Legit Control**:
- Version each prediction with model version, input data, confidence
- Track prediction accuracy over time
- Rollback to previous model if new version underperforms
- Prove prediction methodology for regulatory review

### 7. Regulator Scorecard System
**Future**: Transparency ratings for UK regulators
**With Legit Control**:
- Audit trail for rating calculations
- Version control for methodology changes
- Prove fairness and consistency in scoring
- Track official regulator responses and updates

---

## Architectural Integration

### Current Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                     Frontend (Svelte/ElectricSQL)               │
│                     Local-first, offline capable                │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Phoenix Backend (Elixir)                    │
│                     API Gateway, Real-time Channels             │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌─────────────────────┐     ┌─────────────────────┐
│   PostgreSQL        │     │   RunPod (AI)       │
│   (via Ash/Ecto)    │     │   GPU Compute       │
└─────────────────────┘     └─────────────────────┘
```

### With Legit Control

```
┌─────────────────────────────────────────────────────────────────┐
│                     Frontend (Svelte/ElectricSQL)               │
│                     Local-first, offline capable                │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Phoenix Backend (Elixir)                    │
│                     API Gateway, Real-time Channels             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Legit Control SDK Layer                     │   │
│  │  - Version control for AI writes                         │   │
│  │  - Branching for human review                            │   │
│  │  - Audit trail generation                                │   │
│  │  - Rollback capability                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌─────────────────────┐     ┌─────────────────────┐
│   PostgreSQL        │     │   RunPod (AI)       │
│   (via Ash/Ecto)    │     │   GPU Compute       │
└─────────────────────┘     └─────────────────────┘
```

### Data Flow with Governance

1. **AI Execution**: RunPod AI agent generates enrichment/prediction/score
2. **Legit Control Commit**: Phoenix routes change through Legit Control SDK
3. **Branch Creation**: Proposed change isolated for review (if required)
4. **Human Review**: Notified via Phoenix Channels, reviews in ElectricSQL app
5. **Merge/Reject**: Human approves → merged to main; rejects → discarded
6. **Audit Trail**: Complete history preserved for compliance

---

## Use Case Documents

| Document | Focus Area |
|----------|------------|
| [`legit-control-dot-com.md`](./legit-control-dot-com.md) | Core platform capabilities and compliance applications |
| [`architecture.md`](./architecture.md) | Technical integration with RunPod/Phoenix/ElectricSQL |
| [`acm.md`](./acm.md) | Adaptive Case Management for safety compliance plans |
| [`and-safety.md`](./and-safety.md) | Human-in-the-loop governance for safety documents |
| [`and-agents.md`](./and-agents.md) | AI agent frameworks (LangGraph, AutoGen, CrewAI) |
| [`byoc.md`](./byoc.md) | Bring Your Own Compute architecture for enterprise |

---

## Implementation Priority

### Phase 1: Enrichment Governance (High Value, Low Complexity)
- Add Legit Control to AI enrichment pipeline
- Version every case/notice enrichment
- Enable rollback for incorrect AI analysis
- Generate audit reports for professional validators

### Phase 2: Pre-Qualification Audit Trail (High Value, Medium Complexity)
- Version control for risk score calculations
- Branch workflow for score disputes
- Procurement audit trail generation
- Integration with verification reports

### Phase 3: Full Agent Orchestration (High Value, High Complexity)
- LangGraph integration for multi-step workflows
- NeMo Guardrails for AI safety policies
- BYOC architecture for enterprise customers
- Adaptive Case Management for compliance plans

---

## Business Value

### For Enterprise Customers

| Requirement | How Legit Control Helps |
|-------------|------------------------|
| **Regulatory Compliance** | Immutable audit trails prove AI governance |
| **Legal Defensibility** | Show exactly what AI did and human approved |
| **Risk Management** | Rollback capability minimizes AI error impact |
| **Due Diligence** | Prove systematic review of AI outputs |

### For Platform Differentiation

| Competitor Gap | Our Advantage |
|----------------|---------------|
| AI black boxes | Full transparency into AI decisions |
| No audit trail | Immutable history for every change |
| Manual governance | Automated branching and approval workflows |
| No rollback | Safe recovery from AI errors |

### Revenue Opportunities

| Feature | Tier | Price Point |
|---------|------|-------------|
| Basic audit trails | Professional | Included |
| Branching workflows | Enterprise | +£50/month |
| Custom retention policies | Enterprise | +£100/month |
| Compliance report generation | Enterprise | +£200/month |
| BYOC architecture | Enterprise | Custom |

---

## Technical Considerations

### Elixir/Phoenix Integration

```elixir
# Conceptual integration with Ash actions
defmodule EhsEnforcement.AI.EnrichmentService do
  alias LegitControl.SDK

  def enrich_case_with_governance(case, opts \\ []) do
    # Generate AI enrichment
    {:ok, enrichment_data} = generate_enrichment(case)
    
    # Create Legit Control commit
    {:ok, commit} = SDK.create_commit(%{
      agent_id: "enrichment-service-v1",
      action: "enrich_case",
      target_id: case.id,
      proposed_changes: enrichment_data,
      context: %{
        model_version: opts[:model_version],
        confidence_scores: enrichment_data.confidence_scores
      }
    })
    
    # If high-risk change, create branch for review
    if requires_human_review?(enrichment_data) do
      SDK.create_branch(commit, %{
        reviewer_role: "professional_validator",
        auto_merge_after: nil  # Require explicit approval
      })
    else
      SDK.merge_commit(commit)
    end
  end
end
```

### ElectricSQL Sync Considerations

- Legit Control metadata syncs alongside entity data
- Local app shows "pending review" status for branched changes
- Real-time notifications when branches are approved/rejected
- Conflict resolution for concurrent AI and human edits

---

## Next Steps

1. **Evaluate Legit Control SDK** - Request access, review documentation
2. **Proof of Concept** - Integrate with enrichment pipeline
3. **Define Governance Policies** - Which AI actions require human review?
4. **Design Branch Workflows** - UI for reviewing and approving AI changes
5. **Compliance Report Templates** - What auditors need to see

---

## Related Documentation

- [AI Case Context Enrichment](../ai-case-context-enrichment.md) - Primary integration target
- [Contract Pre-Qualification](../contract-prequalification-intelligence.md) - High-value audit trail use case
- [Expert Commentary System](../expert-commentary-system.md) - Human-AI collaboration
- [AI Model Evaluation Framework](../ai-model-evaluation-framework-for-enforcement-enrichment.md) - Model versioning needs

---

## Resources

- [Legit Control Website](https://legitcontrol.com)
- [LangGraph Documentation](https://langchain-ai.github.io/langgraph/)
- [NeMo Guardrails](https://github.com/NVIDIA/NeMo-Guardrails)
- [Adaptive Case Management](https://en.wikipedia.org/wiki/Adaptive_case_management)

---

**Summary**: Legit Control adds the governance layer that transforms our AI features from "helpful tools" to "enterprise-grade, auditable compliance infrastructure." The immutable audit trails, branching workflows, and rollback capabilities are exactly what regulated industries need to trust AI-driven decisions.
