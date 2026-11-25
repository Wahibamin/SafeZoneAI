# Training references

The notebooks here preserve the Colab/R2PPE and Kaggle training workflows for reference. Notebook output cells and execution counts were cleared before publication to avoid leaking run logs, personal data, or credentials. These notebooks are not ready-to-run without licensed data and environment-specific setup.

- `R2PPE_V7_1_Training_Reference.ipynb`: R2PPE V7.1 training and data workflow.
- `Kaggle_Training_Reference.ipynb`: Kaggle resume/drive workflow; use Kaggle Secrets or environment-managed credentials and never paste secrets into notebook cells.
- `r2ppe_alignment_utils.py`: portable helpers for mapping 1-FPS annotation indices to source-video frames and converting COCO/YOLO box geometry.

The derived V7.1 labels have unresolved semantic problems and the latest baseline was near zero. Training should wait until the labels and source rights are reviewed. No training was started to prepare this submission.
