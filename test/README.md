# test — rotate-aws-backups test suite

[Bats](https://github.com/bats-core/bats-core) tests for `rotate-aws-backups`.
The `build` script runs the suite inside the official `bats/bats:latest`
container so no local bats installation is required.

## Running

```sh
# Via the build script (recommended — same environment as CI):
./build

# Skip all other stages and run only tests:
./build --no-lint --no-scan

# Directly with a local bats installation:
bats test/01-dockerfile.bats test/02-functional.bats
```

## Files

| File | Description |
| --- | --- |
| `01-dockerfile.bats` | Static checks on `Dockerfile` and `README.md` content |
| `02-functional.bats` | Functional tests for `src/rotate-aws-backups` |
| `test_helper.bash` | Minimal bats helper sourced by both test files |
| `bin/aws` | Mock AWS CLI — emulates `s3api list-objects-v2` (with pagination) and `s3 rm` |
| `bin/jq` | Mock jq — handles the two filters used by `rotate-aws-backups` |
| `bin/rotate-backups` | Mock rotate-backups — emits `Deleting`/`Preserving` lines against the workdir |

## Test files

### 01-dockerfile.bats

Static assertions that verify the `Dockerfile` and `README.md` contain the
expected content.

| Test | What it checks |
| --- | --- |
| `Dockerfile contains apk upgrade` | `apk upgrade --no-cache --no-interactive` is present |
| `Dockerfile installs jq` | `jq` is listed in the apk add block |
| `Dockerfile contains HEALTHCHECK` | The correct `HEALTHCHECK` interval/timeout/retries line is present |
| `Dockerfile uses rotate-aws-backups as ENTRYPOINT` | `ENTRYPOINT` names `rotate-aws-backups`, not `startup` |
| `Dockerfile has no CMD (mode must be chosen explicitly)` | No `CMD` instruction is present; mode must be passed as a CLI flag |
| `README documents ROTATE_BACKUPS_VERSION build-arg` | The build-arg is mentioned in `README.md` |

### 02-functional.bats

End-to-end tests that execute `src/rotate-aws-backups` directly (not inside
the image) with mocked external commands.

| Test | What it checks |
| --- | --- |
| `--help exits 0` | `-h`/`--help` prints help and exits 0 |
| `-h exits 0` | Short form of the above |
| `--version exits 0` | `-v`/`--version` exits 0 |
| `-v exits 0` | Short form of the above |
| `--cron without bucket exits non-zero` | Scheduler mode validates `BUCKET`/`BUCKET_LIST` before entering crond |
| `rotation calls aws rm for deleted objects (pagination)` | Objects from page 1 (`a`) and page 2 (`c`) are both deleted |
| `dryrun mode does not invoke aws rm` | `DRYRUN=true` produces no entries in the rm log |
| `DELETE_IGNORED=true deletes objects ignored by rotate-backups` | `Ignoring` objects are removed when `DELETE_IGNORED=true` |
| `DELETE_IGNORED=false does not delete objects ignored by rotate-backups` | `Ignoring` objects are kept when `DELETE_IGNORED=false` |
| `path traversal keys are skipped and do not escape WORKDIR` | Keys like `../../etc/evil` are rejected before any `aws s3 rm` call |

## Mock behaviour

### test/bin/aws

Simulates a two-page S3 bucket:

- **Page 1** — returns keys `a` and `b` with `NextContinuationToken: tok1`
- **Page 2** — returns key `c` (no continuation token)
- **`s3 rm`** — appends the target object path to `$AWS_MOCK_RM_LOG`

### test/bin/jq

Handles the two filter expressions used by `rotate-aws-backups`:

- `.Contents[]?.Key` — extracts all key strings from the JSON page
- `.NextContinuationToken // empty` — extracts the pagination token, or
  produces no output when absent

### test/bin/rotate-backups

Emits one line per file in the workdir directory:

- `a` → `Deleting` (both pagination pages are tested this way)
- `b` → `Preserving`
- `c` → `Deleting`

Individual tests that need different behaviour (e.g. `Ignoring`) create their
own local mock in `$TEST_TMPDIR/bin/` and set `ROTATE_BACKUPS_CMD` accordingly.

## test/staging

A standalone integration script that exercises `rotate-aws-backups` end-to-end
against a real Docker image with no stubs.  Tests that require a live S3 bucket
are skipped (not failed) when `BUCKET` is unset or credentials are unavailable.

### Usage

```sh
# AWS-independent smoke tests only (no credentials needed):
test/staging 1121citrus/rotate-aws-backups:dev-<sha>

# Fast iteration — skip Trivy and Grype:
test/staging --no-scan 1121citrus/rotate-aws-backups:dev-<sha>

# Skip Trivy but still run Grype advisory:
test/staging --no-scan --advise 1121citrus/rotate-aws-backups:dev-<sha>

# Full suite against a dedicated test bucket:
test/staging --bucket test.my-backups \
    --aws-config ~/.secrets/aws-config \
    1121citrus/rotate-aws-backups:dev-<sha>

# Skip the e2e rotation test (requires s3:CreateBucket):
test/staging --bucket my-backups --skip-e2e \
    1121citrus/rotate-aws-backups:dev-<sha>

# Run a single test:
test/staging --test test_staging_trivy_scan \
    1121citrus/rotate-aws-backups:dev-<sha>

# Full help:
test/staging --help
```

### Options

| Flag | Default | Description |
| --- | --- | --- |
| `IMAGE` (positional) | — | Docker image under test |
| `--image IMAGE` | `$IMAGE` env | Docker image under test |
| `--bucket BUCKET` | `$BUCKET` env | Production S3 bucket (read-only dry-run) |
| `--bucket-list LIST` | `$BUCKET_LIST` env | Space-separated bucket list |
| `--aws-config FILE` | `~/.secrets/aws-config` | AWS config/credentials file |
| `--dryrun` / `--no-dryrun` | `true` | Dry-run mode for production bucket tests |
| `--scan` / `--no-scan` | `true` | Trivy HIGH/CRITICAL image scan (gating) |
| `--advise` / `--no-advise` | `true`¹ | Grype full-severity advisory scan (non-gating) |
| `--yes` | false | Skip the interactive confirmation prompt |
| `--skip-e2e` | false | Skip `test_staging_rotation_e2e` |
| `--test TEST` | — | Run only the named test function |
| `--help` | — | Print usage and exit |

¹ Defaults to `false` when `--no-scan` is given without an explicit `--advise`.

### Tests

| Test | AWS required | What it checks |
| --- | --- | --- |
| `test_staging_help` | No | `--help` exits 0 and prints `Usage:` |
| `test_staging_version` | No | `--version` exits 0 and prints the version string |
| `test_staging_unknown_option` | No | An unknown flag exits non-zero |
| `test_staging_no_bucket_cli_mode` | No | CLI mode without a bucket exits non-zero |
| `test_staging_cron_no_bucket` | No | `--cron` without a bucket exits non-zero |
| `test_staging_cli_dryrun` | Yes | One dry-run rotation pass completes successfully |
| `test_staging_cron_fires` | Yes | Scheduler container fires a full rotation within 4 minutes |
| `test_staging_rotation_e2e` | Yes² | Creates a transient bucket, populates it with 10 objects, rotates live, verifies exactly 3 remain |
| `test_staging_trivy_scan` | No | Trivy finds no unfixed HIGH/CRITICAL CVEs (gating) |
| `test_staging_grype_advise` | No | Grype advisory scan completes; findings are printed but never block the run |

² Also requires `s3:CreateBucket`, `s3:PutObject`, and `s3:DeleteBucket` on
`arn:aws:s3:::test.staging.backups.rotate-aws-backups-*`.

### IAM permissions

| Operation | Required permission | Resource |
| --- | --- | --- |
| Production dry-run | `s3:ListBucket` | `arn:aws:s3:::${BUCKET}` and `arn:aws:s3:::${BUCKET}/*` |
| E2E rotation | All of the above, plus `s3:CreateBucket`, `s3:DeleteBucket`, `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` | `arn:aws:s3:::test.staging.backups.rotate-aws-backups-*` |

### Safety

- Buckets not starting with `test.` or `staging.` have `DRYRUN` forced to
  `true` regardless of the `--no-dryrun` flag.
- `test_staging_rotation_e2e` always runs with `DRYRUN=false` on its own
  transient bucket (`test.staging.backups.rotate-aws-backups-<epoch>`), which is removed in a
  `RETURN` trap even on failure.
- A preflight check rejects images that use the legacy shell-form
  `ENTRYPOINT ["/bin/sh","-c"]`, directing the user to rebuild with `./build`.

## Environment variables used by the test setup

| Variable | Set by | Purpose |
| --- | --- | --- |
| `INCLUDE_DIR` | `setup()` | Points to `src/include` so the script can source `common-functions` |
| `AWS_CMD` | `setup()` | Path to `test/bin/aws` |
| `JQ_CMD` | `setup()` | Path to `test/bin/jq` |
| `ROTATE_BACKUPS_CMD` | individual tests | Path to `test/bin/rotate-backups` (or a per-test mock) |
| `AWS_MOCK_RM_LOG` | `setup()` | Path where the aws mock records `s3 rm` invocations |
| `TEST_TMPDIR` | `setup()` | Temporary directory cleaned up in `teardown()` |
