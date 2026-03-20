#!/usr/bin/env bats

load "test_helper"

setup() {
  repo_root=$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)
}

@test "Dockerfile contains apk upgrade" {
  run grep -F "apk upgrade --no-cache --no-interactive" "${repo_root}/Dockerfile"
  [ "$status" -eq 0 ]
}

@test "Dockerfile installs jq" {
  run grep -F "jq" "${repo_root}/Dockerfile"
  [ "$status" -eq 0 ]
}

@test "Dockerfile contains HEALTHCHECK" {
  run grep -F "HEALTHCHECK --interval=60s --timeout=5s --retries=3" "${repo_root}/Dockerfile"
  [ "$status" -eq 0 ]
}

@test "Dockerfile uses rotate-aws-backups as ENTRYPOINT" {
  run grep -F 'ENTRYPOINT ["/usr/local/bin/rotate-aws-backups"]' "${repo_root}/Dockerfile"
  [ "$status" -eq 0 ]
}

@test "Dockerfile has no CMD (mode must be chosen explicitly)" {
  run grep -E '^CMD ' "${repo_root}/Dockerfile"
  [ "$status" -ne 0 ]
}

@test "README documents ROTATE_BACKUPS_VERSION build-arg" {
  run grep -F "ROTATE_BACKUPS_VERSION" "${repo_root}/README.md"
  [ "$status" -eq 0 ]
}
