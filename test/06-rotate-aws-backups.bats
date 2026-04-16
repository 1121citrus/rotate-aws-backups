#!/usr/bin/env bats

# test/06-rotate-aws-backups.bats — option-parsing unit tests for
# src/rotate-aws-backups.
#
# Exercises CLI flags that 02-functional.bats skips in favour of env vars,
# and covers option-argument validation error paths.  Each test targets a
# specific case statement branch or guard line that is otherwise unreachable
# by the functional suite.
#
# Copyright (C) 2026 James Hanlon [mailto:jim@hanlonsoftware.com]
# SPDX-License-Identifier: AGPL-3.0-or-later

load "test_helper"

setup() {
    repo_root=$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    # Isolate env-file reads/writes from the real ~/.env.
    export ENV="${TEST_TMPDIR}/.env"
    mkdir -p "${TEST_TMPDIR}/bin"
    cp "${repo_root}/test/bin/aws"            "${TEST_TMPDIR}/bin/aws"
    cp "${repo_root}/test/bin/rotate-backups" "${TEST_TMPDIR}/bin/rotate-backups"
    cp "${repo_root}/test/bin/jq"             "${TEST_TMPDIR}/bin/jq"
    chmod +x "${TEST_TMPDIR}/bin/aws" \
             "${TEST_TMPDIR}/bin/rotate-backups" \
             "${TEST_TMPDIR}/bin/jq"
    # Minimal supercronic mock: prints the crontab file and exits so
    # scheduler-mode tests can inspect the generated schedule without
    # exec'ing a real supercronic process.
    printf '%s\n' '#!/usr/bin/env bash' 'cat "$1"' \
        > "${TEST_TMPDIR}/bin/supercronic"
    chmod +x "${TEST_TMPDIR}/bin/supercronic"
    export PATH="${TEST_TMPDIR}/bin:${PATH}"
    export AWS_MOCK_RM_LOG="${TEST_TMPDIR}/aws-rm.log"
    export INCLUDE_DIR="${repo_root}/src/include"
    export AWS_CMD="${TEST_TMPDIR}/bin/aws"
    export JQ_CMD="${TEST_TMPDIR}/bin/jq"
    export ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups"
    # Default bucket used by most tests; override per-test when needed.
    export BUCKET=test-bucket
    export BUCKET_LIST=test-bucket
    # Shorthand for the script under test.
    RAB="${repo_root}/src/rotate-aws-backups"
    export RAB
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

# ---------------------------------------------------------------------------
# Options requiring an argument — error when argument is absent
# ---------------------------------------------------------------------------

@test "--cron-expression requires an argument" {
    run bash "${RAB}" --cron-expression
    [ "$status" -ne 0 ]
}

@test "--bucket requires an argument" {
    run bash "${RAB}" --bucket
    [ "$status" -ne 0 ]
}

@test "--bucket-list requires an argument" {
    run bash "${RAB}" --bucket-list
    [ "$status" -ne 0 ]
}

@test "--aws-config requires an argument" {
    run bash "${RAB}" --aws-config
    [ "$status" -ne 0 ]
}

@test "--aws-credentials requires an argument" {
    run bash "${RAB}" --aws-credentials
    [ "$status" -ne 0 ]
}

@test "--aws-extra-args requires an argument" {
    run bash "${RAB}" --aws-extra-args
    [ "$status" -ne 0 ]
}

@test "--hourly requires an argument" {
    run bash "${RAB}" --hourly
    [ "$status" -ne 0 ]
}

@test "--daily requires an argument" {
    run bash "${RAB}" --daily
    [ "$status" -ne 0 ]
}

@test "--weekly requires an argument" {
    run bash "${RAB}" --weekly
    [ "$status" -ne 0 ]
}

@test "--monthly requires an argument" {
    run bash "${RAB}" --monthly
    [ "$status" -ne 0 ]
}

@test "--yearly requires an argument" {
    run bash "${RAB}" --yearly
    [ "$status" -ne 0 ]
}

@test "--timestamp-pattern requires an argument" {
    run bash "${RAB}" --timestamp-pattern
    [ "$status" -ne 0 ]
}

@test "--rotate-backups-extra-args requires an argument" {
    run bash "${RAB}" --rotate-backups-extra-args
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Execution-control flags
# ---------------------------------------------------------------------------

@test "--no-dryrun flag enables live deletion" {
    # --no-dryrun sets DRYRUN=false; confirm_live_run returns early (no tty).
    run bash "${RAB}" --no-dryrun
    [ "$status" -eq 0 ]
    run grep -F "s3://test-bucket/a" "${AWS_MOCK_RM_LOG}"
    [ "$status" -eq 0 ]
}

@test "--dryrun flag keeps dry-run mode enabled" {
    run bash "${RAB}" --dryrun
    [ "$status" -eq 0 ]
    if [ -f "${AWS_MOCK_RM_LOG}" ]; then
        [ "$(wc -l < "${AWS_MOCK_RM_LOG}")" -eq 0 ]
    fi
}

@test "--yes flag is accepted and run completes" {
    run bash "${RAB}" --yes
    [ "$status" -eq 0 ]
}

@test "-y flag is accepted and run completes" {
    run bash "${RAB}" -y
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Grouping flags
# ---------------------------------------------------------------------------

@test "--group flag enables timestamp grouping" {
    run bash "${RAB}" --group
    [ "$status" -eq 0 ]
}

@test "--no-group flag disables timestamp grouping" {
    run bash "${RAB}" --no-group
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Object-filter flags
# ---------------------------------------------------------------------------

@test "--delete-ignored flag deletes objects with no recognisable timestamp" {
    # rotate-backups mock that marks 'a' as ignored.
    cat > "${TEST_TMPDIR}/bin/rotate-backups-ignore" << 'MOCKEOF'
#!/usr/bin/env bash
dir="${*: -1}"
echo "Ignoring ${dir}/a .."
echo "Preserving ${dir}/b .."
MOCKEOF
    chmod +x "${TEST_TMPDIR}/bin/rotate-backups-ignore"
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups-ignore"
    run env DRYRUN=false bash "${RAB}" --delete-ignored
    [ "$status" -eq 0 ]
    run grep -F "s3://test-bucket/a" "${AWS_MOCK_RM_LOG}"
    [ "$status" -eq 0 ]
}

@test "--no-delete-ignored flag preserves objects with no recognisable timestamp" {
    cat > "${TEST_TMPDIR}/bin/rotate-backups-ignore" << 'MOCKEOF'
#!/usr/bin/env bash
dir="${*: -1}"
echo "Ignoring ${dir}/a .."
echo "Preserving ${dir}/b .."
MOCKEOF
    chmod +x "${TEST_TMPDIR}/bin/rotate-backups-ignore"
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups-ignore"
    run env DRYRUN=false bash "${RAB}" --no-delete-ignored
    [ "$status" -eq 0 ]
    if [ -f "${AWS_MOCK_RM_LOG}" ]; then
        run grep -F "s3://test-bucket/a" "${AWS_MOCK_RM_LOG}"
        [ "$status" -ne 0 ]
    fi
}

# ---------------------------------------------------------------------------
# Bucket-selection flags
# ---------------------------------------------------------------------------

@test "--bucket BUCKET derives BUCKET_LIST when --bucket-list is absent" {
    # With BUCKET and BUCKET_LIST both empty, --bucket sets BUCKET and the
    # derivation block at the end of the parser assigns BUCKET_LIST="${BUCKET}".
    run env BUCKET= BUCKET_LIST= DRYRUN=false \
        bash "${RAB}" --bucket test-bucket
    [ "$status" -eq 0 ]
    run grep -F "s3://test-bucket/a" "${AWS_MOCK_RM_LOG}"
    [ "$status" -eq 0 ]
}

@test "--bucket-list LIST sets the bucket list explicitly" {
    run bash "${RAB}" --bucket-list "test-bucket"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AWS-configuration flags
# ---------------------------------------------------------------------------

@test "--aws-config FILE sets the AWS config file path" {
    # /dev/null is always readable; the mock aws ignores AWS_CONFIG_FILE.
    run bash "${RAB}" --aws-config /dev/null
    [ "$status" -eq 0 ]
}

@test "--aws-credentials FILE sets the AWS credentials file path" {
    # /dev/null is always readable; the mock aws ignores
    # AWS_SHARED_CREDENTIALS_FILE.
    run bash "${RAB}" --aws-credentials /dev/null
    [ "$status" -eq 0 ]
}

@test "--aws-extra-args ARGS are accepted" {
    run bash "${RAB}" --aws-extra-args "--region us-east-1"
    [ "$status" -eq 0 ]
}

@test "--rotate-backups-extra-args ARGS are accepted" {
    run bash "${RAB}" --rotate-backups-extra-args "--verbose"
    [ "$status" -eq 0 ]
}

@test "--timestamp-pattern PATTERN sets the timestamp regex" {
    run bash "${RAB}" \
        --timestamp-pattern \
        '(?P<year>\d{4})(?P<month>\d{2})(?P<day>\d{2})'
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Scheduler-mode flags (each implies --cron / CRON_MODE=true)
# ---------------------------------------------------------------------------

@test "--cron-expression EXPR enters scheduler mode with custom schedule" {
    run bash "${RAB}" --cron-expression "@weekly"
    [ "$status" -eq 0 ]
    [[ "$output" == *"@weekly /usr/local/bin/rotate-aws-backups"* ]]
}

@test "--hourly N implies scheduler mode" {
    run bash "${RAB}" --hourly 12
    [ "$status" -eq 0 ]
}

@test "--daily N implies scheduler mode" {
    run bash "${RAB}" --daily 14
    [ "$status" -eq 0 ]
}

@test "--weekly N implies scheduler mode" {
    run bash "${RAB}" --weekly 8
    [ "$status" -eq 0 ]
}

@test "--monthly N implies scheduler mode" {
    run bash "${RAB}" --monthly 12
    [ "$status" -eq 0 ]
}

@test "--yearly N implies scheduler mode" {
    run bash "${RAB}" --yearly 5
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Parser edge cases
# ---------------------------------------------------------------------------

@test "-- stops option parsing; trailing args are not treated as flags" {
    # After --, --bucket is not parsed; BUCKET_LIST remains unset → error.
    run env BUCKET= BUCKET_LIST= bash "${RAB}" -- --bucket test-bucket
    [ "$status" -ne 0 ]
}

@test "unexpected positional argument exits non-zero" {
    run bash "${RAB}" some-unexpected-argument
    [ "$status" -ne 0 ]
}
