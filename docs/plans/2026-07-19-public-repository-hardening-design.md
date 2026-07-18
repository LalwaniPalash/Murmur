# Public Repository Hardening Design

## Goal

Make Murmur safe and understandable to publish without making the repository feel like a company-managed open-source program. It should read like a careful side project: easy to build, honest about its limitations, and light on process.

## Approach

Use the smallest useful public-repository setup. A docs-only cleanup would leave clean-clone packaging broken, while a full release platform with templates, bots, badges, and automated notarization would be disproportionate. The chosen middle ground adds only the files needed to make the source credible and reproducible.

## Licensing and attribution

- Add the standard MIT license with `Copyright (c) 2026 Palash Lalwani`.
- Add a short third-party notices file for whisper.cpp and its GGML components used in local release builds.
- Keep attribution factual and link to upstream projects and licenses.

## Local release checks

Keep verification local instead of adding GitHub Actions. One small script runs the tests, arm64 release build, packaging, signature check, and DMG verification before a release is uploaded manually. There are no badges, coverage gates, release bots, templates, or hosted CI minutes.

## Runtime reproducibility

- Add a small script that downloads a pinned whisper.cpp source archive, verifies its SHA-256 digest, builds the Apple Silicon runtime, and stages the files under the ignored `Vendor/Runtimes/arm64` directory.
- Keep models out of the repository. They continue to be downloaded and verified by the app.
- Make the packaging script fail clearly when `whisper-cli` or its required local libraries are missing instead of producing an incomplete app.
- Document the bootstrap command and required local build tools.
- Do not require or stage unrelated runtimes for the current v2 dictation path.

## Public-facing cleanup

- Update the README for Small English onboarding, the Models page, ignored runtime artifacts, and the actual build flow.
- Keep the tone direct and personal. Avoid badges, marketing claims, contribution bureaucracy, or an oversized roadmap.
- Remove competitor-clone and pixel-copy phrasing from the current design documents. Describe Murmur as its own local voice-writing experiment.
- Retain the legacy source for now, but label it clearly as non-building reference.

## Verification

- Run the runtime staging script from an empty staging directory.
- Package the app and verify the runtime is bundled, arm64, and signed.
- Run the complete Swift test suite and arm64 release build.
- Validate the local release check, license text, notices, README links, secret scan, and clean Git state.
