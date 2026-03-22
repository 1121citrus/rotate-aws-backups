#!/usr/bin/env bats

load "test_helper"

setup() {
  repo_root=$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  mkdir -p "${TEST_TMPDIR}/bin"
  cp "${repo_root}/test/bin/aws" "${TEST_TMPDIR}/bin/aws"
  cp "${repo_root}/test/bin/rotate-backups" "${TEST_TMPDIR}/bin/rotate-backups"
  chmod +x "${TEST_TMPDIR}/bin/aws" "${TEST_TMPDIR}/bin/rotate-backups"
  export PATH="${TEST_TMPDIR}/bin:${PATH}"
  export AWS_MOCK_RM_LOG="${TEST_TMPDIR}/aws-rm.log"
  # Point script to project's include dir so it can source common-functions during tests
  export INCLUDE_DIR="${repo_root}/src/include"
  # Use mock aws and jq explicitly
  cp "${repo_root}/test/bin/jq" "${TEST_TMPDIR}/bin/jq"
  chmod +x "${TEST_TMPDIR}/bin/jq"
  export AWS_CMD="${TEST_TMPDIR}/bin/aws"
  export JQ_CMD="${TEST_TMPDIR}/bin/jq"
}

teardown() {
  rm -rf "${TEST_TMPDIR}"
}

# ---------------------------------------------------------------------------
# CLI flag tests
# ---------------------------------------------------------------------------

@test "--help exits 0" {
  run bash "${repo_root}/src/rotate-aws-backups" --help
  [ "$status" -eq 0 ]
}

@test "-h exits 0" {
  run bash "${repo_root}/src/rotate-aws-backups" -h
  [ "$status" -eq 0 ]
}

@test "--version exits 0" {
  run bash "${repo_root}/src/rotate-aws-backups" --version
  [ "$status" -eq 0 ]
}

@test "-v exits 0" {
  run bash "${repo_root}/src/rotate-aws-backups" -v
  [ "$status" -eq 0 ]
}

@test "--cron without bucket exits non-zero" {
  # Scheduler mode requires BUCKET or BUCKET_LIST; error out without them.
  run env \
    BUCKET= \
    BUCKET_LIST= \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups" --cron
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Rotation tests
# ---------------------------------------------------------------------------

@test "rotation calls aws rm for deleted objects (pagination)" {
  run env \
    BUCKET=test-bucket \
    BUCKET_LIST=test-bucket \
    DRYRUN=false \
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups" \
    AWS_CMD="${AWS_CMD}" \
    JQ_CMD="${JQ_CMD}" \
    AWS_MOCK_RM_LOG="${AWS_MOCK_RM_LOG}" \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups"
  echo "---- script stdout/stderr ----"
  echo "$output"
  echo "---- aws rm log ----"
  if [ -f "${AWS_MOCK_RM_LOG}" ]; then cat "${AWS_MOCK_RM_LOG}"; else echo "(missing) ${AWS_MOCK_RM_LOG}"; fi
  # fail test if script exited non-zero
  [ "$status" -eq 0 ]
  # Ensure rm log contains deletion of 'a' (from first page) and 'c' (from second page)
  run grep -F "s3://test-bucket/a" "${AWS_MOCK_RM_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "s3://test-bucket/c" "${AWS_MOCK_RM_LOG}"
  [ "$status" -eq 0 ]
}

@test "dryrun mode does not invoke aws rm" {
  # DRYRUN=true (the default) must not produce any aws s3 rm calls.
  run env \
    BUCKET=test-bucket \
    BUCKET_LIST=test-bucket \
    DRYRUN=true \
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups" \
    AWS_CMD="${AWS_CMD}" \
    JQ_CMD="${JQ_CMD}" \
    AWS_MOCK_RM_LOG="${AWS_MOCK_RM_LOG}" \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups"
  [ "$status" -eq 0 ]
  # rm log must be absent or empty
  if [ -f "${AWS_MOCK_RM_LOG}" ]; then
    run wc -l < "${AWS_MOCK_RM_LOG}"
    [ "$output" -eq 0 ]
  fi
}

@test "DELETE_IGNORED=true deletes objects ignored by rotate-backups" {
  # Create a custom rotate-backups mock that marks 'a' as Ignoring.
  cat > "${TEST_TMPDIR}/bin/rotate-backups-ignore" << 'EOF'
#!/usr/bin/env bash
dir="${*: -1}"
dir="${dir:-/tmp}"
echo "Ignoring ${dir}/a .."
echo "Preserving ${dir}/b .."
EOF
  chmod +x "${TEST_TMPDIR}/bin/rotate-backups-ignore"

  run env \
    BUCKET=test-bucket \
    BUCKET_LIST=test-bucket \
    DRYRUN=false \
    DELETE_IGNORED=true \
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups-ignore" \
    AWS_CMD="${AWS_CMD}" \
    JQ_CMD="${JQ_CMD}" \
    AWS_MOCK_RM_LOG="${AWS_MOCK_RM_LOG}" \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups"
  [ "$status" -eq 0 ]
  # 'a' was ignored by rotate-backups; DELETE_IGNORED=true must still rm it
  run grep -F "s3://test-bucket/a" "${AWS_MOCK_RM_LOG}"
  [ "$status" -eq 0 ]
}

@test "DELETE_IGNORED=false does not delete objects ignored by rotate-backups" {
  # Create the same ignoring mock.
  cat > "${TEST_TMPDIR}/bin/rotate-backups-ignore" << 'EOF'
#!/usr/bin/env bash
dir="${*: -1}"
dir="${dir:-/tmp}"
echo "Ignoring ${dir}/a .."
echo "Preserving ${dir}/b .."
EOF
  chmod +x "${TEST_TMPDIR}/bin/rotate-backups-ignore"

  run env \
    BUCKET=test-bucket \
    BUCKET_LIST=test-bucket \
    DRYRUN=false \
    DELETE_IGNORED=false \
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups-ignore" \
    AWS_CMD="${AWS_CMD}" \
    JQ_CMD="${JQ_CMD}" \
    AWS_MOCK_RM_LOG="${AWS_MOCK_RM_LOG}" \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups"
  [ "$status" -eq 0 ]
  # 'a' is ignored and DELETE_IGNORED=false — rm log must not contain it
  if [ -f "${AWS_MOCK_RM_LOG}" ]; then
    run grep -F "s3://test-bucket/a" "${AWS_MOCK_RM_LOG}"
    [ "$status" -ne 0 ]
  fi
}

@test "--help mentions --yes" {
  run bash "${repo_root}/src/rotate-aws-backups" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yes"* ]]
}

@test "YES=true with DRYRUN=false bypasses confirmation and runs live" {
  # confirm_live_run is a no-op when YES=true; rotation must complete normally.
  run env \
    BUCKET=test-bucket \
    BUCKET_LIST=test-bucket \
    DRYRUN=false \
    YES=true \
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups" \
    AWS_CMD="${AWS_CMD}" \
    JQ_CMD="${JQ_CMD}" \
    AWS_MOCK_RM_LOG="${AWS_MOCK_RM_LOG}" \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups"
  [ "$status" -eq 0 ]
  run grep -F "s3://test-bucket/a" "${AWS_MOCK_RM_LOG}"
  [ "$status" -eq 0 ]
}

@test "backup set: all files with the same timestamp are deleted together" {
  # Two files share timestamp 20260101T000000 — they form one backup set.
  # A third file has a different timestamp and should be preserved.
  # When rotate-backups marks the representative of the day-1 set for deletion,
  # both day-1 files must be deleted; the day-2 file must not be touched.
  cat > "${TEST_TMPDIR}/bin/aws-grouped" << 'EOF'
#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
cmd="$1"; shift || true
if [[ "$cmd" = "s3api" && "$1" = "list-objects-v2" ]]; then
    cat <<'JSON'
{
  "Contents": [
    { "Key": "20260101T000000-switch.tar.gz" },
    { "Key": "20260101T000000-switch.tar.sha1" },
    { "Key": "20260102T000000-switch.tar.gz" }
  ]
}
JSON
    exit 0
fi
if [[ "$cmd" = "s3" && "$1" = "rm" ]]; then
    shift
    logfile="${AWS_MOCK_RM_LOG:-/tmp/rm.log}"
    echo "$*" >> "$logfile"
    exit 0
fi
echo "aws mock: unsupported: $cmd $*" >&2
exit 2
EOF
  chmod +x "${TEST_TMPDIR}/bin/aws-grouped"

  # rotate-backups sees only the representative of each group:
  #   20260101T000000-switch.tar.gz  → representative of the day-1 set
  #   20260102T000000-switch.tar.gz  → representative of the day-2 set (preserve)
  cat > "${TEST_TMPDIR}/bin/rotate-backups-grouped" << 'EOF'
#!/usr/bin/env bash
dir="${*: -1}"
dir="${dir:-/tmp}"
echo "Deleting ${dir}/20260101T000000-switch.tar.gz .."
echo "Preserving ${dir}/20260102T000000-switch.tar.gz .."
EOF
  chmod +x "${TEST_TMPDIR}/bin/rotate-backups-grouped"

  run env \
    BUCKET=test-bucket \
    BUCKET_LIST=test-bucket \
    DRYRUN=false \
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups-grouped" \
    AWS_CMD="${TEST_TMPDIR}/bin/aws-grouped" \
    JQ_CMD="${JQ_CMD}" \
    AWS_MOCK_RM_LOG="${AWS_MOCK_RM_LOG}" \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups"
  [ "$status" -eq 0 ]

  # Both day-1 files must be deleted.
  run grep -F "s3://test-bucket/20260101T000000-switch.tar.gz" "${AWS_MOCK_RM_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "s3://test-bucket/20260101T000000-switch.tar.sha1" "${AWS_MOCK_RM_LOG}"
  [ "$status" -eq 0 ]

  # Day-2 file must not be deleted.
  if [ -f "${AWS_MOCK_RM_LOG}" ]; then
    run grep -F "s3://test-bucket/20260102T000000-switch.tar.gz" "${AWS_MOCK_RM_LOG}"
    [ "$status" -ne 0 ]
  fi
}

@test "backup set: preserving representative preserves all group members" {
  # When rotate-backups preserves the representative, no member of the set
  # should appear in the rm log.
  cat > "${TEST_TMPDIR}/bin/aws-grouped-preserve" << 'EOF'
#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
cmd="$1"; shift || true
if [[ "$cmd" = "s3api" && "$1" = "list-objects-v2" ]]; then
    cat <<'JSON'
{
  "Contents": [
    { "Key": "20260101T000000-switch.tar.gz" },
    { "Key": "20260101T000000-switch.tar.sha1" }
  ]
}
JSON
    exit 0
fi
if [[ "$cmd" = "s3" && "$1" = "rm" ]]; then
    shift
    logfile="${AWS_MOCK_RM_LOG:-/tmp/rm.log}"
    echo "$*" >> "$logfile"
    exit 0
fi
echo "aws mock: unsupported: $cmd $*" >&2
exit 2
EOF
  chmod +x "${TEST_TMPDIR}/bin/aws-grouped-preserve"

  cat > "${TEST_TMPDIR}/bin/rotate-backups-preserve-all" << 'EOF'
#!/usr/bin/env bash
dir="${*: -1}"
dir="${dir:-/tmp}"
echo "Preserving ${dir}/20260101T000000-switch.tar.gz .."
EOF
  chmod +x "${TEST_TMPDIR}/bin/rotate-backups-preserve-all"

  run env \
    BUCKET=test-bucket \
    BUCKET_LIST=test-bucket \
    DRYRUN=false \
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups-preserve-all" \
    AWS_CMD="${TEST_TMPDIR}/bin/aws-grouped-preserve" \
    JQ_CMD="${JQ_CMD}" \
    AWS_MOCK_RM_LOG="${AWS_MOCK_RM_LOG}" \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups"
  [ "$status" -eq 0 ]

  # Neither file should have been deleted.
  if [ -f "${AWS_MOCK_RM_LOG}" ]; then
    run grep -cF "s3://test-bucket/" "${AWS_MOCK_RM_LOG}"
    [ "$output" -eq 0 ]
  fi
}

@test "--help mentions --no-group" {
  run bash "${repo_root}/src/rotate-aws-backups" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--no-group"* ]]
}

@test "--no-group: files with same timestamp are rotated independently" {
  # With GROUP_BY_TIMESTAMP=false the two day-1 files are independent objects.
  # rotate-backups only sees (and marks) the .tar.gz; the .tar.sha1 is a
  # separate entry and must NOT be deleted by grouping logic.
  cat > "${TEST_TMPDIR}/bin/aws-grouped" << 'EOF'
#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
cmd="$1"; shift || true
if [[ "$cmd" = "s3api" && "$1" = "list-objects-v2" ]]; then
    cat <<'JSON'
{
  "Contents": [
    { "Key": "20260101T000000-switch.tar.gz" },
    { "Key": "20260101T000000-switch.tar.sha1" }
  ]
}
JSON
    exit 0
fi
if [[ "$cmd" = "s3" && "$1" = "rm" ]]; then
    shift
    logfile="${AWS_MOCK_RM_LOG:-/tmp/rm.log}"
    echo "$*" >> "$logfile"
    exit 0
fi
echo "aws mock: unsupported: $cmd $*" >&2
exit 2
EOF
  chmod +x "${TEST_TMPDIR}/bin/aws-grouped"

  # rotate-backups sees both files independently; deletes only the .tar.gz.
  cat > "${TEST_TMPDIR}/bin/rotate-backups-nogroup" << 'EOF'
#!/usr/bin/env bash
dir="${*: -1}"
dir="${dir:-/tmp}"
echo "Deleting  ${dir}/20260101T000000-switch.tar.gz .."
echo "Preserving ${dir}/20260101T000000-switch.tar.sha1 .."
EOF
  chmod +x "${TEST_TMPDIR}/bin/rotate-backups-nogroup"

  run env \
    BUCKET=test-bucket \
    BUCKET_LIST=test-bucket \
    DRYRUN=false \
    GROUP_BY_TIMESTAMP=false \
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups-nogroup" \
    AWS_CMD="${TEST_TMPDIR}/bin/aws-grouped" \
    JQ_CMD="${JQ_CMD}" \
    AWS_MOCK_RM_LOG="${AWS_MOCK_RM_LOG}" \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups"
  [ "$status" -eq 0 ]

  # Only the .tar.gz should have been deleted.
  run grep -F "s3://test-bucket/20260101T000000-switch.tar.gz" "${AWS_MOCK_RM_LOG}"
  [ "$status" -eq 0 ]

  # The .tar.sha1 must NOT be deleted (rotate-backups preserved it independently).
  run grep -F "s3://test-bucket/20260101T000000-switch.tar.sha1" "${AWS_MOCK_RM_LOG}"
  [ "$status" -ne 0 ]
}

@test "path traversal keys are skipped and do not escape WORKDIR" {
  # Create an aws mock that returns a key with a path-traversal component.
  cat > "${TEST_TMPDIR}/bin/aws-traversal" << 'EOF'
#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
cmd="$1"; shift || true
if [[ "$cmd" = "s3api" && "$1" = "list-objects-v2" ]]; then
    cat <<'JSON'
{
  "Contents": [ { "Key": "../../etc/evil" }, { "Key": "safe-backup" } ]
}
JSON
    exit 0
fi
if [[ "$cmd" = "s3" && "$1" = "rm" ]]; then
    shift
    logfile="${AWS_MOCK_RM_LOG:-/tmp/rm.log}"
    echo "$*" >> "$logfile"
    exit 0
fi
echo "aws mock: unsupported: $cmd $*" >&2
exit 2
EOF
  chmod +x "${TEST_TMPDIR}/bin/aws-traversal"

  run env \
    BUCKET=test-bucket \
    BUCKET_LIST=test-bucket \
    DRYRUN=false \
    ROTATE_BACKUPS_CMD="${TEST_TMPDIR}/bin/rotate-backups" \
    AWS_CMD="${TEST_TMPDIR}/bin/aws-traversal" \
    JQ_CMD="${JQ_CMD}" \
    AWS_MOCK_RM_LOG="${AWS_MOCK_RM_LOG}" \
    INCLUDE_DIR="${INCLUDE_DIR}" \
    bash "${repo_root}/src/rotate-aws-backups"
  [ "$status" -eq 0 ]
  # The traversal key must not appear in any rm invocation
  if [ -f "${AWS_MOCK_RM_LOG}" ]; then
    run grep -F "../../etc/evil" "${AWS_MOCK_RM_LOG}"
    [ "$status" -ne 0 ]
  fi
}
