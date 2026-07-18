# Menu Bar Settings Loop Fix

## Problem

On first launch, Murmur consumes roughly one CPU core and continually grows in memory while macOS shows a busy cursor. A live process sample shows SwiftUI repeatedly rebuilding the main menu and `MenuBarExtra`. During that rebuild, SwiftUI writes the current `isInserted` value back through Murmur's binding. Murmur's binding setter calls `updateSettings` even when the value is unchanged, which republishes the observable environment and starts another menu rebuild.

## Chosen design

Make `AppEnvironment.updateSettings` idempotent for every setting:

1. Copy the current `MurmurSettingsRecord` into a local candidate.
2. Apply the requested mutation to the candidate.
3. Return without publishing, applying UI side effects, or persisting when the candidate equals the current record.
4. Assign, apply Flow Bar settings, and persist only when the record actually changed.

This fixes the menu-bar loop at the state boundary and also protects every settings control from redundant SwiftUI binding writes. `MurmurSettingsRecord` already conforms to `Equatable`, so no model change is needed.

## Alternatives considered

- Guard only the menu-bar binding. This would fix the immediate symptom but leave other settings bindings able to publish identical values.
- Replace `MenuBarExtra` with a custom AppKit status item. This offers more control but introduces unnecessary lifecycle and accessibility complexity.

## Verification

- Add a unit-testable settings mutation helper that reports whether a candidate differs from the original.
- Cover both identical writes and actual changes.
- Run the complete Swift test suite and an arm64 release build.
- Repackage and validate the app signature and bundled runtime.
- Relaunch the replacement build and confirm Murmur stays responsive with low idle CPU and stable memory.
