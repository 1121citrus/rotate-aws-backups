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
#     stat stub (outputs STAT_MTIME, default the current epoch time, so a
#     file appears fresh unless a test sets STAT_MTIME to an old time)
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
    # stat stub: outputs STAT_MTIME, or the current epoch time when unset,
    #   so file ages are controlled by the test rather than the filesystem.
    STUB_DIR="${TEST_TMPDIR}/stubs"
    mkdir -p "${STUB_DIR}"
    printf '#!/bin/sh\nexec /bin/true\n' > "${STUB_DIR}/pgrep"
    chmod +x "${STUB_DIR}/pgrep"
    printf '#!/bin/sh\necho "${STAT_MTIME:-$(date +%%s)}"\n' \
        > "${STUB_DIR}/stat"
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
}

@test "healthcheck: exits non-zero when supercronic not running" {
    printf '%s\n' '@daily /usr/local/bin/rotate-aws-backups' \
        > /var/spool/cron/crontabs/rotate-aws-backups
    # Omit STUB_DIR from PATH so real pgrep finds no supercronic process.
    run env DEBUG=true \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
}

@test "healthcheck: exits non-zero when backup has not run (no marker)" {
    printf '%s\n' '@daily /usr/local/bin/rotate-aws-backups' \
        > /var/spool/cron/crontabs/rotate-aws-backups
    run env DEBUG=true \
        PATH="${STUB_DIR}:${PATH}" \
        HEALTHCHECK_SUCCESS_FILE="${TEST_TMPDIR}/nonexistent-marker" \
        HEALTHCHECK_START_FILE="${TEST_TMPDIR}/nonexistent-start" \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
}

@test "healthcheck: exits 0 before the first rotation of a new scheduler" {
    printf '%s\n' '@daily /usr/local/bin/rotate-aws-backups' \
        > /var/spool/cron/crontabs/rotate-aws-backups
    touch "${TEST_TMPDIR}/started"
    run env DEBUG=true \
        PATH="${STUB_DIR}:${PATH}" \
        HEALTHCHECK_SUCCESS_FILE="${TEST_TMPDIR}/nonexistent-marker" \
        HEALTHCHECK_START_FILE="${TEST_TMPDIR}/started" \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -eq 0 ]
}

@test "healthcheck: exits non-zero when no rotation succeeded a cycle after start" {
    printf '%s\n' '@daily /usr/local/bin/rotate-aws-backups' \
        > /var/spool/cron/crontabs/rotate-aws-backups
    touch "${TEST_TMPDIR}/started"
    run env DEBUG=true \
        PATH="${STUB_DIR}:${PATH}" \
        STAT_MTIME=$(($(date +%s) - 90001)) \
        HEALTHCHECK_SUCCESS_FILE="${TEST_TMPDIR}/nonexistent-marker" \
        HEALTHCHECK_START_FILE="${TEST_TMPDIR}/started" \
        bash "${REPO_ROOT}/src/healthcheck"
    [ "$status" -ne 0 ]
}
