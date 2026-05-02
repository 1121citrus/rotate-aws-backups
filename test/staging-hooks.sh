#!/usr/bin/env bash
# shellcheck shell=bash

# test/staging-hooks.sh — repo-specific helpers and test implementations
# for the rotate-aws-backups staging harness (test/staging).
#
# Called by: test/staging (generated) via `source staging-hooks.sh`
# Provides:  setup_hooks() — docker-run helpers
#            test_staging_* — repo-specific test functions
#
# The generated test/staging provides: scan/advise tests, setup(), run_tests(),
# main(). This file provides only what is repo-specific.

# _days_ago_ts prints a timestamp N days ago at noon UTC (YYYYMMDDThhmmss).
# Handles GNU date (Linux) and BSD date (macOS).
_days_ago_ts() {
    local n="$1"
    date -u -d "${n} days ago" '+%Y%m%dT120000' 2>/dev/null || \
    date -u -v-"${n}"d '+%Y%m%dT120000'
}

# ---------------------------------------------------------------------------
# setup_hooks — defines docker-run helpers used by test functions.
# Called by setup() in the generated harness after credentials are ready.
# Exported env vars from setup(): _aws_cfg_mount, _aws_creds_mount, _scan_tar
# ---------------------------------------------------------------------------
setup_hooks() {
    # Run rotate-aws-backups with staging credentials and the given CLI args.
    # Note: the container uses BUCKET (not S3_BUCKET_NAME) as its env var.
    # shellcheck disable=SC2120
    run_rotate_aws_backups() {
        local args=()
        _append_aws_mounts args
        # shellcheck disable=SC2086
        docker run --rm ${DOCKER_RUN_ARGS:-} \
            -e "BUCKET=${S3_BUCKET_NAME:-}" \
            -e "BUCKET_LIST=${BUCKET_LIST:-}" \
            -e "DRYRUN=${DRYRUN:-true}" \
            "${args[@]}" \
            "${IMAGE}" "$@" 2>&1
    }

    # Start the full service container (scheduler mode) detached.
    run_service_detached() {
        local args=()
        _append_aws_mounts args
        # shellcheck disable=SC2086
        docker run -d ${DOCKER_RUN_ARGS:-} \
            -e "BUCKET=${S3_BUCKET_NAME:-}" \
            -e "BUCKET_LIST=${BUCKET_LIST:-}" \
            -e "DRYRUN=${DRYRUN:-true}" \
            "${args[@]}" \
            "$@" \
            "${IMAGE}"
    }

    # Run an aws CLI command inside the image, bypassing the entrypoint.
    # Note: rotate-aws-backups is Alpine-based; aws CLI is at /usr/local/bin/aws.
    _aws() {
        local args=()
        _append_aws_mounts args
        # shellcheck disable=SC2086
        docker run --rm --entrypoint /usr/local/bin/aws \
            ${DOCKER_RUN_ARGS:-} \
            "${args[@]}" \
            -e "AWS_RETRY_MODE=standard" \
            -e "AWS_MAX_ATTEMPTS=5" \
            "${IMAGE}" "$@"
    }

    export -f _aws run_rotate_aws_backups run_service_detached
}

# ---------------------------------------------------------------------------
# CLI / smoke tests (no AWS required)
# ---------------------------------------------------------------------------

test_staging_no_bucket_cli_mode() {
    local result=0
    docker run --rm "${IMAGE}" > /dev/null 2>&1 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': CLI mode without bucket exits non-zero"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero without bucket"
        return 1
    fi
}

test_staging_cron_no_bucket() {
    local result=0
    docker run --rm "${IMAGE}" --cron > /dev/null 2>&1 || result=$?
    if [[ ${result} -ne 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': --cron without bucket exits non-zero"
    else
        echo "FAIL '${FUNCNAME[0]}': should have exited non-zero without bucket"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# AWS-dependent tests
# ---------------------------------------------------------------------------

test_staging_cli_dryrun() {
    printf '  starting CLI dry-run rotation (DRYRUN=%s)...\n' \
        "${DRYRUN:-true}" >&2

    local output result=0
    output=$(run_rotate_aws_backups 2>&1) || result=$?

    if [[ ${result} -ne 0 ]]; then
        echo "FAIL '${FUNCNAME[0]}': rotate-aws-backups exited non-zero (${result})"
        printf '  -- full output --\n' >&2
        printf '%s\n' "${output}" >&2
        printf '  -- end output --\n' >&2
        return 1
    fi
    if echo "${output}" | grep -q 'completed.*bucket rotation'; then
        echo "PASS '${FUNCNAME[0]}': CLI rotation completed (DRYRUN=${DRYRUN:-true})"
    else
        echo "FAIL '${FUNCNAME[0]}': 'completed.*bucket rotation' not found in output"
        printf '  -- full output --\n' >&2
        printf '%s\n' "${output}" >&2
        printf '  -- end output --\n' >&2
        return 1
    fi
}

test_staging_cron_fires() {
    local container_id
    container_id=$(run_service_detached -e "CRON_EXPRESSION=* * * * *")
    printf '  container %s started; waiting for first cron rotation (up to 2m)...\n' \
        "${container_id:0:12}" >&2

    local result=0
    _wait_for_log_pattern "${container_id}" 'completed.*bucket rotation' 120 \
        || result=$?

    docker stop "${container_id}" > /dev/null 2>&1
    docker rm   "${container_id}" > /dev/null 2>&1

    if [[ ${result} -eq 0 ]]; then
        echo "PASS '${FUNCNAME[0]}': cron rotation completed within ${_WAIT_ELAPSED}s" \
             "(DRYRUN=${DRYRUN:-true})"
    else
        echo "FAIL '${FUNCNAME[0]}': rotation did not complete within 120s"
        return 1
    fi
}

# test_staging_rotation_e2e: creates a transient bucket, populates it with 20
# synthetic objects (2 per event), rotates with DAILY=7, and verifies exactly
# 6 objects remain.  The transient bucket is always deleted in a RETURN trap.
test_staging_rotation_e2e() {
    local epoch test_bucket
    epoch=$(date +%s)
    test_bucket="test.rotate-aws-backups-${epoch}"

    # shellcheck disable=SC2064
    trap "_aws s3 rb 's3://${test_bucket}' --force > /dev/null 2>&1 || true" \
        RETURN

    local _region
    _region=$(_aws configure get region 2>/dev/null) || _region="us-east-1"
    printf '  creating transient test bucket s3://%s (region: %s)...\n' \
        "${test_bucket}" "${_region}" >&2
    local _bucket_out _bucket_result=0
    if [[ "${_region}" == "us-east-1" ]]; then
        _bucket_out=$(_aws s3api create-bucket \
            --bucket "${test_bucket}" 2>&1) || _bucket_result=$?
    else
        _bucket_out=$(_aws s3api create-bucket \
            --bucket "${test_bucket}" \
            --region "${_region}" \
            --create-bucket-configuration \
                "LocationConstraint=${_region}" 2>&1) || _bucket_result=$?
    fi
    if [[ ${_bucket_result} -ne 0 ]]; then
        echo "FAIL '${FUNCNAME[0]}': could not create bucket" \
             "(check s3:CreateBucket on test.rotate-aws-backups-*)"
        printf '  %s\n' "${_bucket_out}" >&2
        return 1
    fi

    printf '  uploading 20 synthetic backup objects (2 per event)...\n' >&2
    local i ts ext
    for i in 1 2 3 60 61 62 63 64 65 66; do
        ts=$(_days_ago_ts "${i}")
        for ext in tar.gz tar.sha1; do
            _aws s3api put-object \
                --bucket "${test_bucket}" \
                --key "backup-${ts}.${ext}" \
                > /dev/null 2>&1 || {
                echo "FAIL '${FUNCNAME[0]}': could not upload backup-${ts}.${ext}"
                return 1
            }
        done
    done

    printf '  running live rotation (DAILY=7, no other retention)...\n' >&2
    local rot_output rot_result=0
    local args=()
    _append_aws_mounts args
    # shellcheck disable=SC2086
    rot_output=$(docker run --rm ${DOCKER_RUN_ARGS:-} \
        -e "BUCKET=${test_bucket}" \
        -e "DRYRUN=false" \
        -e "HOURLY=0" \
        -e "DAILY=7" \
        -e "WEEKLY=0" \
        -e "MONTHLY=0" \
        -e "YEARLY=0" \
        -e "DELETE_IGNORED=false" \
        "${args[@]}" \
        "${IMAGE}" 2>&1) || rot_result=$?

    if [[ ${rot_result} -ne 0 ]]; then
        echo "FAIL '${FUNCNAME[0]}': rotation exited non-zero (${rot_result})"
        printf '%s\n' "${rot_output}" | tail -10 >&2
        return 1
    fi

    local remaining=0
    remaining=$(_aws s3 ls "s3://${test_bucket}/" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "${remaining}" -eq 6 ]]; then
        echo "PASS '${FUNCNAME[0]}': ${remaining}/20 objects remain" \
             "(14 old objects correctly deleted in matched pairs)"
    else
        echo "FAIL '${FUNCNAME[0]}': ${remaining}/20 objects remain (expected 6)"
        printf 'Remaining objects:\n' >&2
        _aws s3 ls "s3://${test_bucket}/" >&2 2>&1 || true
        printf 'Rotation output (last 10 lines):\n' >&2
        printf '%s\n' "${rot_output}" | tail -10 >&2
        return 1
    fi
}
