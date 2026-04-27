#!/usr/bin/env bats
# shellcheck shell=bash
# test/07-source-coverage.bats — direct-execution coverage tests.
#
# Run source scripts directly (not via Docker) so kcov can instrument them.
# These tests complement the docker-based integration tests in 01–06 and are
# designed to exercise as many code paths as possible without network access.
#
# Coverage targets:
#   src/healthcheck   (21 lines)
#
# src/startup and src/rotate each contain a single exec line that requires
# /usr/local/bin/rotate-aws-backups to be present; those scripts are not
# directly instrumentable in the bats-kcov container and are omitted.
#
# healthcheck strategy:
#   - setup() symlinks /usr/local/include/common-functions from the repo copy
#   - STUB_DIR contains a pgrep stub (exit 0 = supercronic running) and a
#     stat stub (outputs current epoch time so any marker appears fresh)
#   - Tests that need supercronic absent omit STUB_DIR from PATH so the real
#     pgrep finds no supercronic process in the test container
#   - Crontab hardcoded to /var/spool/cron/crontabs/rotate-aws-backups

setup() {
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
    TEST_TMPDIR=$(mktemp -d)
    export REPO_ROOT TEST_TMPDIR

    # Install common-functions at the absolute path the scripts hardcode.
    mkdir -p /usr/local/include
    ln -sfn "${REPO_ROOT}/src/include/common-functions" \
        /usr/local/include/common-functions

    # Crontab directory: healthcheck reads a hardcoded path here.
    mkdir -p /var/spool/cron/crontabs

    # pgrep stub: simulate supercronic running (exit 0).
    # stat stub: outputs current epoch time so the marker_age ≈ 0 (fresh).
    #   The healthcheck uses `stat -f %m` (macOS); the bats-kcov container is
    #   Alpine Linux where that flag is unsupported.  Returning current time
    #   makes any marker_age < 90000, so the freshness check succeeds.
    STUB_DIR="${TEST_TMPDIR}/stubs"
    mkdir -p "${STUB_DIR}"
    printf '#!/bin/sh\nexec /bin/true\n' > "${STUB_DIR}/pgrep"
    chmod +x "${STUB_DIR}/pgrep"
    printf '#!/bin/sh\ndate +%%s\n' > "${STUB_DIR}/stat"
    chmod +x "${STUB_DIR}/stat"
    export STUB_DIR
}

teardown() {
    rm -rf "${TEST_TMPDIR:-}"
}

# ── src/healthcheck ───────────────────────────────────────────────────────────

@test "healthcheck: exits 0 when crontab ok, supercronic mocked, fresh marker" {
    printf '%s\n' '@daily /usr/local/bin/rotate-aws-backups' \
        > /var/spool/cron/crontabs/rotate-aws-backups
    marker="${TEST_TMPDIR}/marker"
    touch "${marker}"
    run env DEBUG=true \
        PATH="${STUB_DIR}:${PATH}" \
        HEALTHCHECK_SUCCESS_FILE="${marker}" \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -eq 0 ]
}

@test "healthcheck: exits non-zero when crontab not configured" {
    rm -f /var/spool/cron/crontabs/rotate-aws-backups
    run env DEBUG=true \
        PATH="${STUB_DIR}:${PATH}" \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"crontab is not configured"* ]]
}

@test "healthcheck: exits non-zero when supercronic not running" {
    printf '%s\n' '@daily /usr/local/bin/rotate-aws-backups' \
        > /var/spool/cron/crontabs/rotate-aws-backups
    # Omit STUB_DIR from PATH so real pgrep finds no supercronic process.
    run env DEBUG=true \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"supercronic is not running"* ]]
}

@test "healthcheck: exits non-zero when backup has not run (no marker)" {
    printf '%s\n' '@daily /usr/local/bin/rotate-aws-backups' \
        > /var/spool/cron/crontabs/rotate-aws-backups
    run env DEBUG=true \
        PATH="${STUB_DIR}:${PATH}" \
        HEALTHCHECK_SUCCESS_FILE="${TEST_TMPDIR}/nonexistent-marker" \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not run recently"* ]]
}
