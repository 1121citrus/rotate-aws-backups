# rotate-aws-backups

Yet another version of[`rotate-backups`](https://pypi.org/project/rotate-backups/) but this time applied to an AWS S3 backup archive bucket. The `rotate-aws-backups` service would likely be used in conjunction with some other backup service, such as [docker-volume-backup](https://github.com/jareware/docker-volume-backup).

### Method

1. Create a directory (`WORKDIR`) that will servce as as mirror of the bucket.

2. For each object in the bucket, create an empty file in the `WORKDIR` with the same name.

3. Run `rotate-backups` on the `WORKDIR` .

4. Monitor the `rotate-backups` output to delete obects in the bucket that it deletes in the `WORKDIR`.

**[FIXME]** since any storage backend with `ls` and `rm` operations will suffice, abstract to support other backends easily.

## Environment variables

| Variable                               | Default                                                                                              | Possible Values             | Notes                                                                                                                                                                                                                                                                                                                                                                   |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AWS_ACCESS_KEY_ID`                    | none                                                                                                 | any string                  | AWS credentials                                                                                                                                                                                                                                                                                                                                                         |
| `AWS_SECRET_ACCESS_KEY`                | none                                                                                                 | any string                  | AWS credentials                                                                                                                                                                                                                                                                                                                                                         |
| `AWS_S3_BUCKET_NAME`                   | none                                                                                                 | any string                  | AWS bucket to rotate                                                                                                                                                                                                                                                                                                                                                    |
| `ROTATE_AWS_BACKUPS_CRON_EXPRESSION`   | `@daily`                                                                                             | string                      | Standard debian-flavored cron expression for when the backup should run. Use e.g. `0 4 * * *` to back up at 4 AM every night. See the man page or crontab.guru for more.                                                                                                                                                                                                |
| `ROTATE_AWS_BACKUPS_DAILY`             | `7`                                                                                                  | any integer, `always`       | Number of daily backups to preserve.                                                                                                                                                                                                                                                                                                                                    |
| `ROTATE_AWS_BACKUPS_DEBUG`             | `false`                                                                                              | `true`, `false`             | Enable/Disable to set/clear the shall -x (display command) and -v (verbose) options                                                                                                                                                                                                                                                                                     |
| `ROTATE_AWS_BACKUPS_DELETE_IGNORED`    | `false`                                                                                              | `true`, `false`             | Enable/Disable deletion of files that are ignored by `rotate-backups`                                                                                                                                                                                                                                                                                                   |
| `ROTATE_AWS_BACKUPS_DRY_RUN`           | `false`                                                                                              | `true`, `false`             | The dry-run option must explicitly be deactivated by means of `DRY_RUN=false` in order to remove backups.                                                                                                                                                                                                                                                               |
| `ROTATE_AWS_BACKUPS_HOURLY`            | `0`                                                                                                  | any integer, `always`       | Number of hourly backups to preserve.                                                                                                                                                                                                                                                                                                                                   |
| `ROTATE_AWS_BACKUPS_MONTHLY`           | `12`                                                                                                 | any integer, `always`       | Number of monthly backups to preserve.                                                                                                                                                                                                                                                                                                                                  |
| `ROTATE_AWS_BACKUPS_TIMESTAMP_PATTERN` | `(?P<year>\d{4})(?P<month>\d{2})(?P<day>\d{2})[Tt](?P<hour>\d{2})(?P<minute>\d{2})(?P<second>\d{2})` | string (regular expression) | Customize the regular expression pattern that is used to match and extract timestamps from filenames. PATTERN is expected to be a Python compatible regular expression that must define the named capture groups ‘year’, ‘month’ and ‘day’ and may define ‘hour’, ‘minute’ and ‘second’. (See [`rotate-backups`](https://pypi.org/project/rotate-backups/) for details) |
| `ROTATE_AWS_BACKUPS_WEEKLY`            | `4`                                                                                                  | any integer, `always`       | Number of weekly backups to preserve.                                                                                                                                                                                                                                                                                                                                   |
| `ROTATE_AWS_BACKUPS_YEARLY`            | `always`                                                                                             | any integer, `always`       | Number of yearly backups to preserve.                                                                                                                                                                                                                                                                                                                                   |
| TZ                                     | UTC                                                                                                  | ISO timezone                |                                                                                                                                                                                                                                                                                                                                                                         |

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
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - ROTATE_AWS_BACKUPS_CRON_EXPRESSION='0 4 * * *'
      - ROTATE_AWS_BACKUPS_DEBUG=false
      - ROTATE_AWS_BACKUPS_DELETE_IGNORED=false
      - ROTATE_AWS_BACKUPS_DRYRUN=false
      - ROTATE_AWS_BACKUPS_HOURLY=24
      - ROTATE_AWS_BACKUPS_DAILY=7
      - ROTATE_AWS_BACKUPS_WEEKLY=8
      - ROTATE_AWS_BACKUPS_MONTHLY=6
      - ROTATE_AWS_BACKUPS_YEARLY=always
      - TZ=US/Eastern
```

### One Shot Rotation

```sh
docker run --rm -it -e AWS_S3_BUCKET_NAME=bucket -e AWS_ACCESS_KEY_ID=access_key -e AWS_SECRET_ACCESS_KEY=secret -e ROTATE_AWS_BACKUPS_DELETE_IGNORED=true -e ROTATE_AWS_BACKUPS_CRON_EXPRESSION='15 2 * * *' 1121citrus/rotate-aws-backups rotate
```


