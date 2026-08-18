// SwiftPM requires at least one source file in a C target. The whisper.cpp and
// GGML symbols themselves come from the staged dylibs in Vendor/Runtimes/arm64/lib,
// which script/stage_whisper_runtime.sh produces. This target only vendors the
// v1.8.4 public headers so Swift can import them as the CWhisper module.
