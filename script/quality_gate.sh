#!/usr/bin/env bash

set -u

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_directory="$(cd "${script_directory}/.." && pwd)"
output_directory="${1:-${repository_directory}/.build/quality}"
benchmark_baseline="${2:-${repository_directory}/quality/baselines/benchmark-report.json}"

mkdir -p "${output_directory}"
cd "${repository_directory}" || exit 1

checks=()
failed=0
incomplete=0

record_result() {
    local identifier="$1"
    local status="$2"
    local summary="$3"
    checks+=("${identifier}=${status}:${summary}")
    printf '%-22s %-8s %s\n' "${identifier}" "${status}" "${summary}"
    if [[ "${status}" == "failed" ]]; then failed=1; fi
    if [[ "${status}" == "notRun" ]]; then incomplete=1; fi
}

run_check() {
    local identifier="$1"
    local summary="$2"
    shift 2
    if "$@" >"${output_directory}/${identifier}.log" 2>&1; then
        record_result "${identifier}" "passed" "${summary}"
    else
        record_result "${identifier}" "failed" "${summary}; see ${identifier}.log"
    fi
}

run_evidence_check() {
    local identifier="$1"
    local passed_summary="$2"
    local incomplete_summary="$3"
    shift 3
    "$@" >"${output_directory}/${identifier}.log" 2>&1
    local status=$?
    if [[ ${status} -eq 0 ]]; then
        record_result "${identifier}" "passed" "${passed_summary}"
    elif [[ ${status} -eq 3 ]]; then
        record_result "${identifier}" "notRun" "${incomplete_summary}; see ${identifier}.log"
    else
        record_result "${identifier}" "failed" "${passed_summary}; see ${identifier}.log"
    fi
}

printf 'Murmur F1 quality gate\nArtifacts: %s\n\n' "${output_directory}"

run_check whitespace "No whitespace errors in the working diff" git diff --check
run_check corpus-manifest "Versioned corpus manifest is valid" \
    swift run murmur-quality corpus validate \
    Tests/MurmurNextTests/Fixtures/AudioCorpus/manifest.json \
    Tests/MurmurNextTests/Fixtures/AudioCorpus
run_check build "Swift debug build succeeds" swift build
run_check tests "Unit and resident integration suites pass" \
    env MURMUR_QUALITY_REPORT_DIR="${output_directory}" swift test
run_check privacy "Canary, diagnostics, preferences, and network privacy regressions pass" \
    swift test --filter 'PrivacyAuditTests|DiagnosticsExportServiceTests|RepositoryPrivacyTests'
run_check network "Only declared model-download and BYOK writing surfaces use networking" \
    swift run murmur-quality network audit Sources/MurmurNext \
    Intelligence/HuggingFaceLocalWritingModelDownloader.swift \
    Intelligence/ModelInstaller.swift \
    Intelligence/OpenAITextTransformationEngine.swift \
    Intelligence/TransformationHTTPClient.swift

if [[ -f "${output_directory}/corpus-quality.json" ]]; then
    run_evidence_check corpus "Corpus has no known completeness failures" \
        "Corpus was skipped because its resident runtime or model is unavailable" \
        swift run murmur-quality corpus evaluate "${output_directory}/corpus-quality.json"
else
    record_result corpus notRun "Corpus report was not produced"
fi

if [[ -f "${output_directory}/benchmark-samples.json" \
      && -f "${output_directory}/pipeline-benchmark-samples.json" ]]; then
    run_check benchmark-artifacts "Whisper and pipeline stage timings were merged" \
        swift run murmur-quality benchmark merge \
        "${output_directory}/combined-benchmark-samples.json" \
        "${output_directory}/benchmark-samples.json" \
        "${output_directory}/pipeline-benchmark-samples.json"
    run_check benchmark-summary "Duration-bucket p50/p95 report was produced" \
        swift run murmur-quality benchmark summarize \
        "${output_directory}/combined-benchmark-samples.json" \
        "${output_directory}/benchmark-report.json"
else
    record_result benchmark-artifacts notRun "Complete pipeline benchmark samples were not produced"
fi

run_evidence_check insertion "Declared insertion matrix meets the 99.5% gate" \
    "Manual insertion rows remain untested" \
    swift run murmur-quality insertion evaluate quality/insertion-matrix.json 0.995

if [[ -f "${benchmark_baseline}" && -f "${output_directory}/benchmark-report.json" ]]; then
    run_evidence_check benchmark "No statistically meaningful p95 regression" \
        "Benchmark sample count is insufficient for comparison" \
        swift run murmur-quality benchmark compare \
        "${output_directory}/benchmark-report.json" "${benchmark_baseline}" \
        "${output_directory}/benchmark-comparison.json" 0.15 5
else
    record_result benchmark notRun "No compatible checked benchmark baseline is available"
fi

swift run murmur-quality gate report "${output_directory}/quality-gate.json" "${checks[@]}" \
    >"${output_directory}/quality-gate.log" 2>&1
gate_status=$?
if [[ ${gate_status} -ne 0 ]]; then
    printf '\nUnable to write quality-gate.json; see quality-gate.log\n'
    exit 1
fi

printf '\nMachine report: %s\n' "${output_directory}/quality-gate.json"
if [[ ${failed} -ne 0 ]]; then exit 1; fi
if [[ ${incomplete} -ne 0 ]]; then exit 3; fi
exit 0
