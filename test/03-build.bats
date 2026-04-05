#!/usr/bin/env bats

# Test suite for the build script.
# Tests option parsing, cache control, and stage execution.

setup() {
    export BUILD_SCRIPT="${BATS_TEST_DIRNAME}/../build"
}

# ============================================================================
# CLI Option Parsing Tests
# ============================================================================

@test "build --help outputs usage information" {
    run "${BUILD_SCRIPT}" --help
    [[ $status -eq 0 ]]
    [[ "$output" == *"SYNOPSIS"* ]]
    [[ "$output" == *"--advise"* ]]
    [[ "$output" == *"--cache"* ]]
}

@test "build rejects unknown options" {
    run "${BUILD_SCRIPT}" --unknown-option 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" == *"Unknown option"* ]]
}

@test "build --version requires an argument" {
    run "${BUILD_SCRIPT}" --version 2>&1
    [[ $status -eq 1 ]]
}

@test "build --platform requires an argument" {
    run "${BUILD_SCRIPT}" --platform 2>&1
    [[ $status -eq 1 ]]
}

@test "build --registry requires an argument" {
    run "${BUILD_SCRIPT}" --registry 2>&1
    [[ $status -eq 1 ]]
}

@test "build --cache requires CACHE_RULES argument" {
    run "${BUILD_SCRIPT}" --cache 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" == *"--cache requires CACHE_RULES"* ]]
}

@test "build --cache rejects argument starting with --" {
    run "${BUILD_SCRIPT}" --cache --advise 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" == *"--cache requires CACHE_RULES"* ]]
}

# ============================================================================
# Advisement Option Parsing Tests
# ============================================================================

@test "build --advise scout enables Scout" {
    run "${BUILD_SCRIPT}" --advise scout --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Stage 5b: Advise (Scout)"* ]]
}

@test "build --advise dive enables Dive" {
    run "${BUILD_SCRIPT}" --advise dive --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Stage 5c: Advise (Dive)"* ]]
}

@test "build --advise Dive enables Dive" {
    run "${BUILD_SCRIPT}" --advise Dive --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Stage 5c: Advise (Dive)"* ]]
}

@test "build --advise DIVE enables Dive" {
    run "${BUILD_SCRIPT}" --advise DIVE --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Stage 5c: Advise (Dive)"* ]]
}

@test "build --advice scout is alias for --advise scout" {
    run "${BUILD_SCRIPT}" --advice scout --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Stage 5b: Advise (Scout)"* ]]
}

@test "build --advise scout,dive enables Scout and Dive" {
    run "${BUILD_SCRIPT}" --advise scout,dive --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Stage 5b: Advise (Scout)"* ]]
    [[ "$output" == *"Stage 5c: Advise (Dive)"* ]]
}

@test "build --advise rejects unknown advisement" {
    run "${BUILD_SCRIPT}" --advise unknown --dry-run 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" == *"Unknown advisement"* ]]
}

@test "build --advise coverage enables coverage advisement" {
    run "${BUILD_SCRIPT}" --advise coverage --dry-run --no-lint --no-scan  2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Stage 5d: Coverage"* ]]
}

@test "build --no-coverage skips Stage 5d" {
    run "${BUILD_SCRIPT}" --no-coverage --dry-run --no-lint --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 5d: Coverage"* ]]
}

@test "build --advice none disables all advisements" {
    run "${BUILD_SCRIPT}" --advice none --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
    [[ "$output" != *"Stage 5d"* ]]
}

@test "build --no-advise disables all advisements" {
    run "${BUILD_SCRIPT}" --no-advise --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
    [[ "$output" != *"Stage 5d"* ]]
}

@test "build --advise none disables all advisements" {
    run "${BUILD_SCRIPT}" --advise none --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
    [[ "$output" != *"Stage 5d"* ]]
}

@test "build --advise NONE disables all advisements" {
    run "${BUILD_SCRIPT}" --advise NONE --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
    [[ "$output" != *"Stage 5d"* ]]
}

@test "build defaults to no advisory scans" {
    run "${BUILD_SCRIPT}" --dry-run --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 5a"* ]]
    [[ "$output" != *"Stage 5b"* ]]
    [[ "$output" != *"Stage 5c"* ]]
    [[ "$output" != *"Stage 5d"* ]]
}

# ============================================================================
# Cache Control Tests
# ============================================================================

@test "build --cache reset=all references both caches" {
    run "${BUILD_SCRIPT}" --cache "reset=all" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Cache: reset Trivy DB"* ]]
    [[ "$output" == *"Cache: reset Grype DB"* ]]
}

@test "build --cache reset=trivy references only Trivy" {
    run "${BUILD_SCRIPT}" --cache "reset=trivy" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Cache: reset Trivy DB"* ]]
}

@test "build --cache reset=grype references only Grype" {
    run "${BUILD_SCRIPT}" --cache "reset=grype" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Cache: reset Grype DB"* ]]
}

@test "build --cache combined rules work" {
    run "${BUILD_SCRIPT}" --cache "reset=trivy;skip-update=grype" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Cache: reset Trivy DB"* ]]
}

@test "build --cache Reset=All references both caches" {
    run "${BUILD_SCRIPT}" --cache "Reset=All" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Cache: reset Trivy DB"* ]]
    [[ "$output" == *"Cache: reset Grype DB"* ]]
}

@test "build --cache Skip-Update=TrIvY skips Trivy DB update" {
    run "${BUILD_SCRIPT}" --cache "Skip-Update=TrIvY" --dry-run --no-lint --no-test 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Trivy DB update skipped"* ]]
}

@test "build --cache rejects invalid rule key" {
    run "${BUILD_SCRIPT}" --cache "invalid-rule=target" --dry-run 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" == *"Unknown --cache rule key"* ]]
}

@test "build --cache rejects invalid target" {
    run "${BUILD_SCRIPT}" --cache "reset=invalid" --dry-run 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" == *"Unknown cache target"* ]]
}

# ============================================================================
# Stage Execution Tests
# ============================================================================

@test "build --dry-run shows Stage 2 Build" {
    run "${BUILD_SCRIPT}" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Stage 2: Build"* ]]
}

@test "build --no-lint skips Stage 1" {
    run "${BUILD_SCRIPT}" --no-lint --dry-run --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 1: Lint"* ]]
}

@test "build --no-test skips Stage 3" {
    run "${BUILD_SCRIPT}" --no-test --dry-run --no-lint --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 3: Test"* ]]
}

@test "build defaults to Stage 3b smoke" {
    run "${BUILD_SCRIPT}" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Stage 3b: Smoke"* ]]
}

@test "build --no-smoke skips Stage 3b" {
    run "${BUILD_SCRIPT}" --no-smoke --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 3b: Smoke"* ]]
}

@test "build --no-scan skips Stage 4" {
    run "${BUILD_SCRIPT}" --no-scan --dry-run --no-lint --no-test --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 4"* ]]
}

@test "build --no-scan skips advisements by default" {
    run "${BUILD_SCRIPT}" --no-scan --dry-run --no-lint --no-test 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"Stage 5a"* ]]
}

# ============================================================================
# Volume Configuration Tests
# ============================================================================

@test "build outputs Trivy volume name at startup" {
    run "${BUILD_SCRIPT}" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Trivy DB:  volume:rotate-aws-backups-trivy-cache"* ]]
}

@test "build outputs Grype volume name at startup" {
    run "${BUILD_SCRIPT}" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Grype DB:  volume:rotate-aws-backups-grype-cache"* ]]
}

@test "build --advise grype does not re-prime a populated Grype cache" {
    command -v docker >/dev/null 2>&1 || skip "docker is required for Grype cache regression test"

    docker volume rm rotate-aws-backups-grype-cache >/dev/null 2>&1 || true
    docker volume create rotate-aws-backups-grype-cache >/dev/null

    run "${BUILD_SCRIPT}" --advise grype --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"Priming Grype DB cache (first run)"* ]]

    run "${BUILD_SCRIPT}" --advise grype --no-lint --no-test --no-scan 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" != *"No Grype DB cache found in volume"* ]]
    [[ "$output" != *"Priming Grype DB cache (first run)"* ]]
}

# ============================================================================
# Quiet Flag Tests
# ============================================================================

@test "build Stage 2 Build shows [DRY RUN] prefix" {
    run "${BUILD_SCRIPT}" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"[DRY RUN]"* ]]
}

# ============================================================================
# Version and Registry Tests
# ============================================================================

@test "build --version sets image tag" {
    run "${BUILD_SCRIPT}" --version 1.2.3 --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"1121citrus/rotate-aws-backups:1.2.3"* ]]
}

@test "build defaults to dev- version" {
    run "${BUILD_SCRIPT}" --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"dev-"* ]]
}

@test "build --registry sets registry" {
    run "${BUILD_SCRIPT}" --registry myregistry --dry-run --no-lint --no-test --no-scan --no-advise 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" == *"myregistry/rotate-aws-backups"* ]]
}

# ============================================================================
# Help Text Tests
# ============================================================================

@test "build --help documents --advise" {
    run "${BUILD_SCRIPT}" --help
    [[ $status -eq 0 ]]
    [[ "$output" == *"--advise"* ]]
}

@test "build --help documents --cache" {
    run "${BUILD_SCRIPT}" --help
    [[ $status -eq 0 ]]
    [[ "$output" == *"--cache CACHE_RULES"* ]]
}

@test "build --help shows reset example" {
    run "${BUILD_SCRIPT}" --help
    [[ $status -eq 0 ]]
    [[ "$output" == *"reset="* ]]
}

@test "build --help shows skip-update example" {
    run "${BUILD_SCRIPT}" --help
    [[ $status -eq 0 ]]
    [[ "$output" == *"skip-update="* ]]
}
