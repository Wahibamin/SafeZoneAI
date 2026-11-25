# Quick usage notes

Run commands from the repository root so that model and database paths stay relative to the project. See the main README for environment setup. A model file must be supplied separately and must match the expected three mask classes and class order.

For development, prefer a local test clip whose license permits use. Do not store raw camera footage or person images in the repository. Event storage uses a local SQLite database; use a new disposable database for demos.

The Android app imports a compatible LiteRT/TFLite model through the in-app library. Model metadata and tensor contract checks are described in `mobile_app/docs/MODEL_CONTRACT.md` and `mobile_app/docs/MODEL_COMPATIBILITY.md`.
