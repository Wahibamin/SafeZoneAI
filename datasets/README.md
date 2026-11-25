# Dataset sources and usage

No dataset, extracted frame, or annotation archive is included in this repository.

## R2PPE

- Official project and code: https://github.com/yangwanzhao/R2PPE-DATASET
- Research paper: https://www.nature.com/articles/s41597-024-04355-0
- The paper describes CC BY 4.0 with possible third-party exceptions. The repository code is GPL-3.0. Verify terms for the exact video, annotations, and any redistributed derived artifacts before use.
- The local V7.1 preparation fixed an annotation-frame indexing error (annotation indices are sampled at 1 FPS, whereas source videos are about 30 FPS). Structural QA passed, but semantic label review found errors and the V7.1 set is **not approved for training**. See [`../docs/R2PPE_ALIGNMENT.md`](../docs/R2PPE_ALIGNMENT.md).

## Other candidate sources

Local PPE dataset archives were reviewed during development, but the exact dataset identity and redistribution license were not consistently documented. Those archives and derived images are omitted. Do not assume that a dataset found through Kaggle, Roboflow, Mendeley, or a paper can be redistributed; check its source-specific terms.

## Preparing data locally

Keep downloaded or derived data under `datasets/source/` or `datasets/derived/` (both are ignored by Git). Keep credentials in local environment variables or the dataset provider's secret manager. Never commit API keys, OAuth files, database files, video, personal images, or raw data archives.
