# Model Management Page Design

## Goal

Make local transcription performance an explicit user choice. Move Whisper model management out of Settings into a first-class Models destination where people can compare, download, activate, and delete verified local models.

## Navigation and layout

Add Models to the primary sidebar after Scratchpad. The page contains:

- a summary showing the active model, installed model count, and total installed storage;
- a highlighted recommendation for Small English;
- English and Multilingual model sections;
- model cards with language, relative speed, quality tier, disk size, installation state, and actions;
- inline download and verification progress;
- failure messaging that remains attached to model management rather than becoming a global persistence error.

The Settings model list is replaced with a short explanation and a button that opens the Models destination.

## Curated catalog

English:

- Tiny English
- Base English
- Small English — recommended default

Multilingual:

- Tiny Multilingual
- Base Multilingual
- Small Multilingual
- Large v3 Turbo Compact Q5
- Large v3 Turbo

Exact file sizes and SHA-256 digests come from the official `ggerganov/whisper.cpp` model repository metadata. Murmur continues to download only over HTTPS, verifies the complete file before activation, and removes partial files after cancellation or failure.

## Lifecycle behavior

- Only one model download runs at a time.
- Download & Use activates the model only after integrity verification succeeds.
- Use switches instantly between verified installed models.
- Deleting an inactive model requires confirmation.
- Deleting the active model requires confirmation and selects the best installed fallback.
- Deleting the final installed model is allowed only after an explicit warning that dictation will be unavailable.
- Active downloads cannot be deleted.
- Existing Large Turbo installations remain installed and active until the user chooses another model.
- New installations and onboarding recommend Small English instead of Large v3 Turbo.

## Testing and release checks

- Verify the expanded manifest catalog, file-name validation, sizes, and digests.
- Cover activation after installation and deterministic fallback after deletion.
- Cover final-model deletion behavior and protected partial downloads.
- Run the complete unit suite and an arm64 release build.
- Package build 5 and validate its signature, runtime, and model catalog behavior.
