# src — rotate-aws-backups source files

Source files copied into the Docker image at build time.

## Files

| File | Destination | Description |
| --- | --- | --- |
| `rotate-aws-backups` | `/usr/local/bin/rotate-aws-backups` | Main command. Runs one rotation pass (CLI mode) or enters scheduler mode with `--cron`; modes are mutually exclusive. |
| `rotate` | `/usr/local/bin/rotate` | Thin wrapper — `exec /usr/local/bin/rotate-aws-backups`. Provides a short synonym for one-off runs. |
| `startup` | `/usr/local/bin/startup` | Compatibility shim for deployments that set `entrypoint: /usr/local/bin/startup`. Calls `rotate-aws-backups --cron`. |
| `healthcheck` | `/usr/local/bin/healthcheck` | Docker `HEALTHCHECK` probe. Verifies `crond` is running and the crontab is configured. |
| `include/common-functions` | `/usr/local/include/common-functions` | Shared bash library — logging, boolean helpers, exit codes. |

## rotate-aws-backups

The main command. Run `rotate-aws-backups --help` for the full option list.

### Quick reference

```text
rotate-aws-backups [options]

  -h,--help                        Display help text
  -v,--version                     Display version

  Scheduling (any one triggers async/periodic execution via crond):
  -c,--cron                        Enter scheduler mode using CRON_EXPRESSION
                                   (default: @daily)
  --cron-expression EXPR           Scheduler mode; use EXPR as the schedule
                                   (env: CRON_EXPRESSION; implies --cron)
  --hourly N / --daily N / --weekly N / --monthly N / --yearly N
                                   Retention counts; each implies --cron

  Bucket selection:
  -b,--bucket BUCKET               S3 bucket to rotate (env: BUCKET)
  --bucket-list LIST               Space-separated bucket list

  Execution control:
  --dryrun / --no-dryrun           Toggle dry-run mode (default: --dryrun)
  --delete-ignored                 Delete timestamp-less objects

  AWS configuration:
  --aws-config FILE                AWS config file
  --aws-extra-args ARGS            Extra aws CLI arguments
  --rotate-backups-extra-args ARGS Extra rotate-backups arguments
  --timestamp-pattern PATTERN      Filename timestamp regex
```

Every option corresponds to an environment variable of the same conceptual
name (e.g. `--daily 14` overrides `DAILY`). CLI flags take precedence.

### Modes

Scheduler mode is triggered by any one of:

| Trigger | Schedule used |
| --- | --- |
| `--cron` | `CRON_EXPRESSION` env var (default: `@daily`) |
| `--cron-expression EXPR` | `EXPR` |
| `CRON_EXPRESSION=EXPR` in environment | `EXPR` |
| `--hourly`, `--daily`, `--weekly`, `--monthly`, `--yearly` | `CRON_EXPRESSION` (default: `@daily`) |

**Scheduler mode**: writes an env file (all config vars except
`CRON_EXPRESSION`, to prevent re-entry on cron-spawned calls), installs a
crontab, and execs `crond`. Output and exit status are those of `crond`. The
crond-invoked jobs run in CLI mode.

**CLI mode** (no scheduling trigger): runs one rotation pass synchronously
and exits. Output and exit status are those of `rotate-aws-backups` itself.

The container image has no default `CMD`; a mode must be chosen explicitly
(e.g. `command: ["--cron"]` in Docker Compose).

### Test mocks

The test suite (`test/`) overrides three commands via environment variables so
no real AWS calls are made:

| Variable | Default | Purpose |
| --- | --- | --- |
| `AWS_CMD` | `aws` | Replaced by `test/bin/aws` mock |
| `JQ_CMD` | `jq` | Replaced by `test/bin/jq` mock |
| `ROTATE_BACKUPS_CMD` | `/usr/local/bin/rotate-backups` | Replaced by `test/bin/rotate-backups` mock |
| `INCLUDE_DIR` | `/usr/local/include` | Points to `src/include` during tests |

## startup

Compatibility shim retained for deployments that set
`entrypoint: /usr/local/bin/startup`. Calls:

```bash
exec /usr/local/bin/rotate-aws-backups --cron "$@"
```

New deployments should use `rotate-aws-backups --cron` directly (e.g.
`command: ["--cron"]` in Docker Compose).

## healthcheck

Called by Docker's `HEALTHCHECK` every 60 seconds. Only meaningful in
scheduler mode. Returns exit 0 if:

- `crond` is running (checked with `pgrep -x crond`), and
- the crontab contains `/usr/local/bin/rotate-aws-backups`.

## include/common-functions

Shared bash library providing:

- Logging functions: `debug`, `info`, `notice`, `warn`, `error`, `fatal`, `trace`, `diag`
- Boolean helpers: `is_true`, `is_false`
- Exit/return code constants: `EXIT_SUCCESS`, `EXIT_ERROR`, `EXIT_USAGE`, etc.

Source it with:

```bash
source "${INCLUDE_DIR:-/usr/local/include}/common-functions"
```
