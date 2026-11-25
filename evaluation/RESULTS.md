# Evaluation snapshots

These records describe past runs. They are not a claim of product accuracy or deployment readiness. The reserved test split was not used in the V7.1 baseline comparisons.

| Run | Split / context | Precision | Recall | mAP50 | mAP50–95 | Interpretation |
|---|---|---:|---:|---:|---:|---|
| `best_mask_v4` baseline | R2PPE V7.1 validation, 640 px | 0.00130 | 0.00270 | 0.000194 | 0.000027 | Near-zero; unresolved label/box compatibility and data-quality concerns |
| `yolo26n` alternate baseline | R2PPE V7.1 validation, 640 px | 0.00284 | 0.02199 | 0.000514 | 0.000107 | Near-zero; not a validated replacement |
| `best_mask_v4` one-epoch smoke | R2PPE V7.1 validation | — | — | 0.0148 | — | Smoke run only; not completed training |
| Historical V4 checkpoint record | Older, different validation setup | 0.83434* | 0.78887* | 0.8604* | 0.5910* | Historical record only; not directly comparable or independent |

`*` Historical V4 figures are recorded in an older experiment summary. A separate inventory records a similar but not identical checkpoint metric (mAP50 0.85737, mAP50–95 0.58876); evaluation protocol and dataset lineage differ from the V7.1 baseline. Treat the older numbers as historical context, not an established benchmark.

The raw baseline summaries and evaluation plots are included in this directory. Per-image predictions, face imagery, detailed logs, and large artifacts are omitted. Model checkpoints are not redistributed because the right to redistribute them could not be confirmed.
