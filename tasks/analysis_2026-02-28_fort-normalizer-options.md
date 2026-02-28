# Fort Normalizer Strategy Matrix - 2026-02-28

## Goal

Handle changing Fort section aliases every 4 weeks without manual alias churn, while preserving deterministic output quality for Mon/Wed/Fri conversion.

## Evaluation Criteria

- Robustness to new section names (40%)
- Determinism / testability (25%)
- Implementation complexity (20%, lower is better)
- Regression risk in existing cycles (15%, lower is better)

Scoring: 1-5 per criterion. Weighted total out of 5.

## Candidate Solutions (12)

1. Expand static alias list continuously
- Robustness: 2
- Determinism: 5
- Complexity: 4
- Risk: 3
- Weighted: 3.30
- Notes: cheap short-term, high maintenance debt.

2. Ask user to provide canonical section mapping each cycle
- Robustness: 5
- Determinism: 5
- Complexity: 3
- Risk: 4
- Weighted: 4.45
- Notes: operationally heavy, poor UX.

3. LLM-only re-labeling pre-pass (no deterministic parser)
- Robustness: 4
- Determinism: 1
- Complexity: 3
- Risk: 2
- Weighted: 2.75
- Notes: high nondeterminism.

4. Regex-only generic unknown header segmentation
- Robustness: 3
- Determinism: 4
- Complexity: 4
- Risk: 3
- Weighted: 3.45
- Notes: helps, but still weak semantic mapping.

5. Embedding similarity against section exemplars
- Robustness: 4
- Determinism: 2
- Complexity: 2
- Risk: 3
- Weighted: 2.95
- Notes: requires model infra and drift handling.

6. Finite-state parser + mandatory section order template
- Robustness: 3
- Determinism: 5
- Complexity: 3
- Risk: 3
- Weighted: 3.60
- Notes: rigid; may fail on unusual programs.

7. Exercise-type classifier only (ignore headers)
- Robustness: 4
- Determinism: 4
- Complexity: 3
- Risk: 3
- Weighted: 3.85
- Notes: misses explicit phase intent where exercise overlap exists.

8. Hybrid: header pattern + dynamic unknown-header inference + exercise semantics + positional priors
- Robustness: 5
- Determinism: 4
- Complexity: 3
- Risk: 4
- Weighted: 4.35
- Notes: best tradeoff for current architecture.

9. Build a trainer-authored YAML schema per cycle
- Robustness: 5
- Determinism: 5
- Complexity: 2
- Risk: 4
- Weighted: 4.20
- Notes: strong but requires process/tooling changes.

10. Self-learning alias cache from previous successful weeks
- Robustness: 4
- Determinism: 3
- Complexity: 2
- Risk: 2
- Weighted: 2.95
- Notes: can reinforce bad mappings.

11. Dual-pass generation with confidence gate and automatic retry prompt
- Robustness: 4
- Determinism: 3
- Complexity: 3
- Risk: 3
- Weighted: 3.45
- Notes: useful but secondary to parsing quality.

12. Hard fail when unknown sections detected (require user intervention)
- Robustness: 5
- Determinism: 5
- Complexity: 5
- Risk: 5
- Weighted: 5.00
- Notes: technically safest but unacceptable UX for autonomous generation.

## Selected Approach

Selected: **#8 Hybrid deterministic normalizer**

Why:
- Strong robustness without operational burden.
- Keeps deterministic behavior and unit-test coverage.
- Integrates cleanly into existing `FortCompiler` and correction loop.

## Implementation Shape

- Introduce unknown-header section segmentation when the parser sees section boundaries but no known alias.
- Infer unknown section role using deterministic cues:
  - modality keywords (conditioning),
  - main-lift/pull-up/accessory/mobility exercise semantics,
  - section position priors.
- Preserve existing alias map as first-class signal, fallback to inferred mapping only when needed.
- Add validation guardrails for supplemental day structure so nonsense mini-days fail correction loop.
