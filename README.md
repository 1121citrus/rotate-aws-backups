# 1121citrus/rotate-aws-backups

Yet another version of [`rotate-backups`](https://pypi.org/project/rotate-backups/) but this time applied to an AWS S3 backup archive bucket. The `rotate-aws-backups` service would likely be used in conjunction with some other backup service, such as [docker-volume-backup](https://github.com/jareware/docker-volume-backup).

The main author of the [Python Rotate Backups](https://pypi.org/project/rotate-backups/) library is [Peter Odding](https://github.com/xolox). The original source code is at [xolox/python-rotate-backups](https://github.com/xolox/python-rotate-backups).

## Contents

- [1121citrus/rotate-aws-backups](#1121citrus-rotate-aws-backups)
  - [Contents](#contents)
  - [Synopsis](#synopsis)
  - [Method](#method)
  - [Examples](#examples)
    - [Docker Compose](#docker-compose)
    - [One Shot Rotation](#one-shot-rotation)
  - [Configuration](#configuration)
  - [Building](#building)

## Synopsis

* Quoting [`rotate-backups`](https://pypi.org/project/rotate-backups/):

> The basic premise of `rotate-backups` is fairly simple:
>
>You point `rotate-backups` at a directory containing timestamped backups.
>It will scan the directory for entries (it doesn’t matter whether they are files or directories) with a recognizable timestamp in the name.
>
> **Note**
>All of the matched directory entries are considered to be backups of the same data source, i.e. there’s no filename similarity logic to distinguish unrelated backups that are located in the same directory. If this presents a problem consider using the `--include` and/or `--exclude` options.
>
>The user defined rotation scheme is applied to the entries. If this doesn’t do what you’d expect it to you can try the `--relaxed` and/or `--prefer-recent` options.
>
>The entries to rotate are removed (or printed in dry run).

* `rotate-aws-backups` only operates on an AWS S3 bucket.

* Credentials are supplied by a compose [secret](https://docs.docker.com/compose/how-tos/use-secrets/).

## Method

1. Create a directory (`WORKDIR`) that will serve as as mirror of the bucket.

2. For each object in the bucket, create an empty file in the `WORKDIR` with the same name.

3. Run [`rotate-backups`](https://pypi.org/project/rotate-backups/) on the `WORKDIR`.

4. Monitor the [`rotate-backups`](https://pypi.org/project/rotate-backups/) output to delete obects in the bucket that it deletes in the `WORKDIR`.

**[FIXME]** since any storage backend with `ls` and `rm` operations will suffice, abstract to support other backends easily.

## Examples

### Docker Compose

```yml
version: "3"

services:
  backup-rotate:
    container_name: rotate-aws-ackups
    image: 1121citrus/rotate-aws-backups
    restart: unless-stopped
    environment:
      - AWS_S3_BUCKET_NAME=${AWS_S3_BUCKET_NAME}
      - CRON_EXPRESSION='0 4 * * *'
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

secrets:
  aws-config:
    file: ./aws-config
```

### One Shot Rotation

```sh
docker run --rm -it -e AWS_S3_BUCKET_NAME=bucket -v ./aws-config:/run/secrets/aws-config 1121citrus/rotate-aws-backups rotate
```

## Configuration

Environment Variable | Default | Possible Values | Notes
--- | --- | --- | ---
`AWS_CONFIG_FILE` | `/run/secrets/aws-config` | path | AWS configuration file (via [secret](https://docs.docker.com/compose/how-tos/use-secrets/) or [bind](https://docs.docker.com/engine/storage/bind-mounts/))
`AWS_EXTRA_ARGS` | none | any string | Additional arguments to pass to `aws` commands
`AWS_S3_BUCKET_NAME` | none | any string | AWS bucket to rotate
`CRON_EXPRESSION` | `@daily` | string | Standard debian-flavored cron expression for when the backup should run. Use e.g. `0 4 * * *` to back up at 4 AM every night. See the man page or crontab.guru for more.                                                                                                                                                                                                `DAILY` | `7` | any integer, `always` | Number of daily backups to preserve.
`DEBUG` | `false` | `true`, `false` | Enable/Disable to set/clear the shall -x (display command) and -v (verbose) options
`DELETE_IGNORED` | `false` | `true`, `false` | Enable/Disable deletion of files that are ignored by `rotate-backups`
`DRYRUN` | `true` | `true`, `false` | The dry-run option must explicitly be deactivated by means of `DRYRUN=false` in order to remove backups.
`HOURLY` | `0`  | any integer, `always` | Number of hourly backups to preserve.
`MONTHLY` | `12` | any integer, `always` | Number of monthly backups to preserve.
`ROTATE_BACKUPS_EXTRA_ARGS` | none | any string | Additional arguments to pass to `rotate-backups` command
`TIMESTAMP_PATTERN` | `(?P<year>\d{4})(?P<month>\d{2})(?P<day>\d{2})[Tt](?P<hour>\d{2})(?P<minute>\d{2})(?P<second>\d{2})` | string (regular expression) | Customize the regular expression pattern that is used to match and extract timestamps from filenames. `TIMESTAMP_PATTERN` is expected to be a Python compatible regular expression that must define the named capture groups ‘year’, ‘month’ and ‘day’ and may define ‘hour’, ‘minute’ and ‘second’. (See [`rotate-backups`](https://pypi.org/project/rotate-backups/) for details)
`WEEKLY` | `4` | any integer, `always` | Number of weekly backups to preserve.
`YEARLY` | `always`| any integer, `always` | Number of yearly backups to preserve.
`TZ` | `UTC` | ISO timezone | 

The AWS credentials are passed through the `aws-config` Docker compose [secret](https://docs.docker.com/compose/how-tos/use-secrets/).
 
## Building

1. `docker buildx build --sbom=true --provenance=true --provenance=mode=max --platform linux/amd64,linux/arm64 --tag 1121citrus/rotate-aws-backups:latest --tag 1121citrus/rotate-aws-backups:MAJOR.MINOR.PATCH --push .`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;**NOTE**: Follow [semantic versioning](https://semver.org) conventions.