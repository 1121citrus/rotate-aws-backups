# 1121citrus/rotate-aws-backups

A CLI command that rotates objects in AWS S3 backup buckets using the
[`rotate-backups`](https://pypi.org/project/rotate-backups/) retention policy
engine. It also supports a built-in scheduler (`--cron`) for running as a
long-lived container service.

The `rotate-aws-backups` command is commonly used alongside a backup service such as [docker-volume-backup](https://github.com/jareware/docker-volume-backup).

## Contents

- [Synopsis](#synopsis)
- [Method](#method)
- [Usage](#usage)
  - [Options](#options)
- [Modes](#modes)
  - [CLI mode](#cli-mode)
  - [Scheduler mode](#scheduler-mode)
- [Examples](#examples)
  - [Command line](#command-line)
  - [Docker Compose](#docker-compose)
- [Configuration](#configuration)
- [Building](#building)
- [Attributions and provenance](#attributions-and-provenance)

## Synopsis

Quoting [`rotate-backups`](https://pypi.org/project/rotate-backups/):

> The basic premise of `rotate-backups` is fairly simple:
>
> You point `rotate-backups` at a directory containing timestamped backups.
> It will scan the directory for entries (it doesn't matter whether they are
> files or directories) with a recognizable timestamp in the name.
>
> **Note:** All of the matched directory entries are considered to be backups
> of the same data source, i.e. there's no filename similarity logic to
> distinguish unrelated backups that are located in the same directory. If
> this presents a problem consider using the `--include` and/or `--exclude`
> options.
>
> The user defined rotation scheme is applied to the entries. If this doesn't
> do what you'd expect it to you can try the `--relaxed` and/or
> `--prefer-recent` options.
>
> The entries to rotate are removed (or printed in dry run).

`rotate-aws-backups` only operates on an AWS S3 bucket. Credentials are supplied by a Docker Compose [secret](https://docs.docker.com/compose/how-tos/use-secrets/).

## Method

1. Create a temporary directory (`WORKDIR`) that serves as a mirror of the bucket.
2. List all objects in the bucket (handling S3 `list-objects-v2` pagination
   transparently, so buckets with more than 1 000 objects are processed correctly).
   Objects that share the same S3 directory prefix **and** timestamp are treated
   as a single backup set: only one representative file is created in `WORKDIR`
   per set, and all member keys are recorded for the next step.
   Objects with no recognisable timestamp each become their own singleton entry.
3. Run [`rotate-backups`](https://pypi.org/project/rotate-backups/) on `WORKDIR`.
4. For every entry that `rotate-backups` marks for deletion, issue `aws s3 rm`
   calls for **every member** of the corresponding backup set — ensuring that
   multi-file backups (e.g. a `.tar.bz2.gpg` and its `.sha1` companion) are
   always deleted or preserved as a unit.

**Dry-run is enabled by default** (`DRYRUN=true`). No objects are deleted
until `DRYRUN=false` is explicitly set (or `--no-dryrun` is passed).

## Usage

```sh
rotate-aws-backups [options]
```

### Options

```text
  -h,--help                        Display this help text
  -v,--version                     Display command version

  Scheduling (any one triggers async/periodic execution via crond):
  -c,--cron                        Enter scheduler mode using CRON_EXPRESSION
                                   (default: @daily)
  --cron-expression EXPR           Scheduler mode; use EXPR as the schedule
                                   (env: CRON_EXPRESSION; implies --cron)
  --hourly N                       Hourly backups to keep; implies --cron
                                   (env: HOURLY; default: 24)
  --daily N                        Daily backups to keep; implies --cron
                                   (env: DAILY; default: 7)
  --weekly N                       Weekly backups to keep; implies --cron
                                   (env: WEEKLY; default: 4)
  --monthly N                      Monthly backups to keep; implies --cron
                                   (env: MONTHLY; default: 6)
  --yearly N                       Yearly backups to keep; implies --cron
                                   (env: YEARLY; default: always)
  --timestamp-pattern PATTERN      Regex for extracting timestamps
                                   (env: TIMESTAMP_PATTERN)

  Bucket selection:
  -b,--bucket BUCKET               S3 bucket to rotate (env: BUCKET)
  --bucket-list LIST               Space-separated bucket list
                                   (env: BUCKET_LIST; default: BUCKET)

  Execution control:
  --dryrun                         Enable dry-run; no deletions made
                                   (env: DRYRUN; default: true)
  --no-dryrun                      Disable dry-run; deletions are live
  -y,--yes                         Skip the interactive confirmation
                                   prompt when DRYRUN=false and stdin
                                   is a tty (env: YES; default: false)
  --delete-ignored                 Delete objects with no recognisable
                                   timestamp (env: DELETE_IGNORED;
                                   default: false)
  --no-delete-ignored              Do not delete ignored objects (default)
  --group                          Group objects by timestamp so that all
                                   files belonging to one backup event are
                                   rotated as a unit (default)
                                   (env: GROUP_BY_TIMESTAMP; default: true)
  --no-group                       Disable grouping; rotate each S3 object
                                   independently (pre-grouping behaviour)

  AWS configuration:
  --aws-config FILE                AWS config file
                                   (env: AWS_CONFIG_FILE;
                                   default: /run/secrets/aws-config)
  --aws-credentials FILE           AWS credentials file
                                   (env: AWS_SHARED_CREDENTIALS_FILE;
                                   default: /run/secrets/aws-credentials)
  --aws-extra-args ARGS            Extra args appended to every aws call
                                   (env: AWS_EXTRA_ARGS)
  --rotate-backups-extra-args ARGS Extra args appended to every
                                   rotate-backups invocation
                                   (env: ROTATE_BACKUPS_EXTRA_ARGS)
```

CLI flags take precedence over environment variables.

## Modes

Any one of the following triggers scheduler mode (async, periodic execution
via `crond`). Without any of them the command runs synchronously — one
rotation pass, then exits.

| Trigger | Schedule used |
| --- | --- |
| `--cron` | `CRON_EXPRESSION` env var (default: `@daily`) |
| `--cron-expression EXPR` | `EXPR` |
| `CRON_EXPRESSION=EXPR` in environment | `EXPR` |
| `--hourly`, `--daily`, `--weekly`, `--monthly`, `--yearly` | `CRON_EXPRESSION` (default: `@daily`) |

### CLI mode

Without any scheduling trigger, `rotate-aws-backups` runs one rotation pass
and exits. Output and exit status are those of `rotate-aws-backups` itself.
Suitable for scripting, externally managed cron jobs, or one-off runs.

When `DRYRUN=false` and stdin is a tty, an interactive confirmation prompt
is shown before any deletions are made. Pass `--yes` (or set `YES=true`) to
skip the prompt — useful for scripting or CI where stdin is not a tty.

```sh
rotate-aws-backups --bucket my-backups --no-dryrun
```

In a container:

```sh
docker run --rm \
  -v ./aws-config:/run/secrets/aws-config \
  1121citrus/rotate-aws-backups \
  --bucket my-backups --no-dryrun
```

### Scheduler mode

Any scheduling trigger causes `rotate-aws-backups` to write all configuration
to an env file, install a crontab entry, and exec `crond`. Output and exit
status are those of `crond`. The crond-spawned jobs run in CLI mode (no
scheduling trigger is passed).

## Examples

### Command line

```sh
# Dry-run (default) — show what would be deleted:
rotate-aws-backups --bucket my-backups

# Live rotation with default retention:
rotate-aws-backups --bucket my-backups --no-dryrun

# Custom retention policy:
rotate-aws-backups --bucket my-backups --no-dryrun \
    --daily 14 --weekly 8 --monthly 12

# Rotate multiple buckets in one pass:
rotate-aws-backups --bucket-list "bucket-a bucket-b" --no-dryrun

# Scheduler mode — daily at midnight (default schedule):
rotate-aws-backups --cron --bucket my-backups --no-dryrun

# Scheduler mode — custom schedule via flag (implies --cron):
rotate-aws-backups --cron-expression "0 4 * * *" \
    --bucket my-backups --no-dryrun
```

### Docker Compose

```yml
version: "3"

services:
  backup-rotate:
    container_name: rotate-aws-backups
    image: 1121citrus/rotate-aws-backups
    restart: unless-stopped
    # Use --cron for scheduler mode, or omit it for a one-shot rotation.
    # Exactly one mode must be chosen; they are mutually exclusive.
    command: ["--cron"]
    environment:
      - BUCKET=${BUCKET}
      - CRON_EXPRESSION=0 4 * * *
      - DRYRUN=false
      - HOURLY=24
      - DAILY=7
      - WEEKLY=8
      - MONTHLY=6
      - YEARLY=always
      - TZ=${TZ}
    volumes:
      - /etc/localtime:/etc/localtime:ro
    secrets:
      - aws-config
      - aws-credentials

secrets:
  aws-config:
    file: ./aws-config
  aws-credentials:
    file: ./aws-credentials
```

## Configuration

All environment variables can be overridden by the corresponding CLI flag.
See [Options](#options) for the flag names.

| Environment variable | Default | Possible values | Notes |
| --- | --- | --- | --- |
| `AWS_CONFIG_FILE` | `/run/secrets/aws-config` | path | AWS configuration file (via [secret](https://docs.docker.com/compose/how-tos/use-secrets/) or [bind](https://docs.docker.com/engine/storage/bind-mounts/)). |
| `AWS_SHARED_CREDENTIALS_FILE` | `/run/secrets/aws-credentials` | path | AWS credentials file (via [secret](https://docs.docker.com/compose/how-tos/use-secrets/) or [bind](https://docs.docker.com/engine/storage/bind-mounts/)). |
| `AWS_EXTRA_ARGS` | _(none)_ | any string | Additional arguments appended to every `aws` invocation. |
| `BUCKET` | _(none)_ | any string | Single AWS S3 bucket to rotate. Mutually usable with `BUCKET_LIST`. |
| `BUCKET_LIST` | _(value of `BUCKET`)_ | space-separated list | One or more AWS S3 buckets to rotate. |
| `CRON_EXPRESSION` | `@daily` | cron expression | Cron schedule. Setting this variable implies scheduler mode (same as `--cron`). Use e.g. `0 4 * * *` for 04:00 every night. See `crontab(5)` or [crontab.guru](https://crontab.guru). |
| `DAILY` | `7` | integer or `always` | Number of daily backups to preserve. |
| `DEBUG` | `false` | `true`, `false` | Enables bash `-x` (xtrace) and `-v` (verbose) modes. |
| `DELETE_IGNORED` | `false` | `true`, `false` | When `true`, objects that `rotate-backups` ignores (no recognisable timestamp) are also deleted. |
| `DRYRUN` | `true` | `true`, `false` | **Must be set to `false` to delete any objects.** When `true` the rotation plan is logged but no `aws s3 rm` calls are made. |
| `GROUP_BY_TIMESTAMP` | `true` | `true`, `false` | When `true` (default), S3 objects that share the same directory prefix and timestamp are treated as one backup set and rotated together. Set to `false` to restore the pre-grouping per-file behaviour (each object rotated independently). See also `--no-group`. |
| `HOURLY` | `24` | integer or `always` | Number of hourly backups to preserve. |
| `MONTHLY` | `6` | integer or `always` | Number of monthly backups to preserve. |
| `ROTATE_BACKUPS_EXTRA_ARGS` | _(none)_ | any string | Additional arguments appended to every `rotate-backups` invocation. |
| `TIMESTAMP_PATTERN` | `(?P<year>\d{4})(?P<month>\d{2})(?P<day>\d{2})[Tt](?P<hour>\d{2})(?P<minute>\d{2})(?P<second>\d{2})` | Python regex | Pattern used to extract timestamps from filenames. Must define named groups `year`, `month`, `day` and optionally `hour`, `minute`, `second`. See [`rotate-backups`](https://pypi.org/project/rotate-backups/) for details. |
| `TZ` | `UTC` | IANA timezone name | Timezone used by crond and timestamp comparisons. |
| `WEEKLY` | `4` | integer or `always` | Number of weekly backups to preserve. |
| `YEARLY` | `always` | integer or `always` | Number of yearly backups to preserve. |
| `YES` | `false` | `true`, `false` | When `true`, skips the interactive confirmation prompt that fires in CLI mode when `DRYRUN=false` and stdin is a tty. Equivalent to `--yes`. |

AWS credentials are supplied via one or both of:

- `aws-config` (pointed to by `AWS_CONFIG_FILE`) — the standard
  [AWS CLI configuration file](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
  containing profiles and region settings.
- `aws-credentials` (pointed to by `AWS_SHARED_CREDENTIALS_FILE`) — the
  standard
  [AWS CLI credentials file](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
  containing `aws_access_key_id` and `aws_secret_access_key`.

In Docker Compose deployments both files are typically mounted as
[secrets](https://docs.docker.com/compose/how-tos/use-secrets/) or
[bind mounts](https://docs.docker.com/engine/storage/bind-mounts/).

## Building

### Development build (local, not pushed)

```sh
./build
```

The `build` script runs linting (hadolint, shellcheck, markdownlint), builds
the image locally, runs bats tests, and scans with Trivy.
See `./build --help` for all flags.

To pin the `rotate-backups` Python package version:

```sh
ROTATE_BACKUPS_VERSION=7.1 ./build
```

### Production build (CI/CD)

See [`.github/CI-WORKFLOWS.md`](.github/CI-WORKFLOWS.md) for the full CI/CD pipeline documentation.

## Attributions and provenance

| Component | Author | Source | License |
| --- | --- | --- | --- |
| [`rotate-backups`](https://pypi.org/project/rotate-backups/) Python library | [Peter Odding](https://github.com/xolox) | [xolox/python-rotate-backups](https://github.com/xolox/python-rotate-backups) | MIT |
| [AWS CLI](https://aws.amazon.com/cli/) | Amazon Web Services | [aws/aws-cli](https://github.com/aws/aws-cli) | Apache-2.0 |
| [jq](https://jqlang.github.io/jq/) | Stephen Dolan et al. | [jqlang/jq](https://github.com/jqlang/jq) | MIT |
| [Alpine Linux](https://alpinelinux.org/) | Alpine Linux contributors | — | Various (MIT/GPL) |
| [Python](https://www.python.org/) | Python Software Foundation | — | PSF-2.0 |
| `rotate-aws-backups` (this project) | James Hanlon | — | AGPL-3.0-or-later |

Published Docker images include an embedded **SBOM** (Software Bill of
Materials) in SPDX format and an **in-toto provenance attestation**
(`mode=max`). These can be inspected with:

```sh
# List attestations
docker buildx imagetools inspect 1121citrus/rotate-aws-backups:latest

# Extract SBOM
docker scout sbom 1121citrus/rotate-aws-backups:latest

# Scan for vulnerabilities
trivy image 1121citrus/rotate-aws-backups:latest
```
