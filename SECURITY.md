# Security

## Threat model

`rotate-aws-backups` is a scheduled maintenance tool that **deletes** S3 objects.
Its trust boundary is: a single, isolated Docker container with outbound network
access to AWS S3 endpoints only.  The primary threat is accidental or malicious
deletion of backup objects.

| Threat | Mitigation |
| --- | --- |
| Accidental mass deletion | `DRYRUN=true` by default; deletion requires explicit opt-in. |
| Credential leakage | Credentials live only in the Docker secret (`aws-config`), never in environment variables or image layers. |
| S3 key path traversal | Keys containing `..` components or a leading `/` are logged as warnings and skipped before any local file is created. |
| Malicious `rotate-backups` output | The script only acts on lines matching `Deleting`/`Ignoring`/`Preserving`; all other output is discarded. |
| Overly permissive IAM | See [Least-privilege IAM](#least-privilege-iam) below. |

## Credentials

AWS credentials are supplied exclusively through a Docker
[secret](https://docs.docker.com/compose/how-tos/use-secrets/) mounted at
`/run/secrets/aws-config` (overridable via `AWS_CONFIG_FILE`). The file
format is the standard AWS CLI configuration file:

```ini
[default]
aws_access_key_id     = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
region                = us-east-1
```

The secret file is **never** written to the `.env` file or logged.

## Least-privilege IAM

Grant the IAM principal only the permissions actually required:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::YOUR-BACKUP-BUCKET"
    },
    {
      "Sid": "DeleteObjects",
      "Effect": "Allow",
      "Action": ["s3:DeleteObject"],
      "Resource": "arn:aws:s3:::YOUR-BACKUP-BUCKET/*"
    }
  ]
}
```

Do **not** grant `s3:*`, `s3:PutObject`, `s3:GetObject`, or any IAM/management permissions.

## Docker hardening

```yaml
services:
  backup-rotate:
    image: 1121citrus/rotate-aws-backups
    read_only: true                # container filesystem is read-only
    security_opt:
      - no-new-privileges:true     # processes cannot gain additional privileges
    tmpfs:
      - /tmp                       # writable scratch space in RAM only
      - /var/spool/cron/crontabs   # crond writes its crontab here at startup
      - /var/log/rotate-aws-backups
    networks:
      - egress-only                # isolated network with outbound-only rules
    secrets:
      - aws-config
```

> **Note:** the container runs as `root` because Alpine's busybox `crond` manages
> per-user crontab files.  Use the `security_opt: no-new-privileges` and
> network isolation above to constrain the blast radius.

## Environment variable injection

All configuration values written to the container's `.env` file are
shell-quoted with `printf '%q'` before being written.  Values containing
single quotes, parentheses, or other shell-special characters are safely
escaped and cannot inject commands when the file is later sourced.

## Supply-chain verification

Every image published to Docker Hub includes:

- An **SPDX SBOM** listing all OS packages and Python libraries.
- An **in-toto provenance attestation** (`mode=max`) that records the exact
  Dockerfile, build arguments, and source commit used.

Verify them with:

```sh
# Inspect attestations
docker buildx imagetools inspect 1121citrus/rotate-aws-backups:latest

# Scan for known CVEs
trivy image 1121citrus/rotate-aws-backups:latest
```

The CI pipeline (`.github/workflows/build-and-push-docker-image.yaml`) runs
`trivy` on every published image and **fails the build** on unfixed
HIGH/CRITICAL vulnerabilities.

## Known vulnerabilities

All seven remaining vulnerabilities are in Alpine APK packages with no
upstream fix available as of **2026-03-20**. They cannot be remediated without
replacing Alpine or the affected APK packages.

**Distinction:** A "fixable" CVE has a patch available but not yet deployed (remediation is possible).
An "unfixed" CVE has no patch available from any vendor (no remediation possible).

| CVE | Package | Severity | Status | Notes |
| --- | --- | --- | --- | --- |
| CVE-2025-66471 | `py3-urllib3 1.26.20-r1` (APK) | HIGH | Not fixed in Alpine | Brought in by `aws-cli` APK; no Alpine fix available. |
| CVE-2025-66418 | `py3-urllib3 1.26.20-r1` (APK) | HIGH | Not fixed in Alpine | Same package/vector as above. |
| CVE-2025-50182 | `py3-urllib3 1.26.20-r1` (APK) | MEDIUM | Not fixed in Alpine | Same package; open-redirect variant. |
| CVE-2025-50181 | `py3-urllib3 1.26.20-r1` (APK) | MEDIUM | Not fixed in Alpine | Same package; open-redirect variant. |
| CVE-2016-2781 | `coreutils 9.7-r1` | MEDIUM | No upstream fix (ever) | Affects the `chroot` command; `chroot` is not used in this container. |
| CVE-2025-60876 | `busybox 1.37.0-r20` | MEDIUM | Not fixed in Alpine | No Alpine fix available. |
| CVE-2026-27171 | `zlib 1.3.1-r2` | LOW | Not fixed in Alpine | No Alpine fix available. |

### Remediation history

The following CVEs were present in earlier releases and have been fixed:

| CVE | Package | Fix applied |
| --- | --- | --- |
| CVE-2026-21441, CVE-2025-66471, CVE-2025-66418, CVE-2025-50181 | `urllib3` (PyPI — rotate-backups runtime) | Pinned `urllib3>=2.6.3` in Python 3.14 env |
| CVE-2026-26007 | `cryptography` (PyPI — rotate-backups runtime) | Pinned `cryptography>=46.0.5` in Python 3.14 env |
| CVE-2024-5569 | `zipp` (PyPI) | Pinned `zipp>=3.19.1` |
| CVE-2024-53427, CVE-2025-48060, CVE-2024-23337 | `jq` (APK) | Base image bump to `python:3.14-alpine3.22` |
| CVE-2025-8869, CVE-2026-1703 | `pip` (system Python) | Upgraded system Python pip to ≥26.0 |
| CVE-2026-26007 | `cryptography` (system Python — aws-cli runtime) | Upgraded via system Python pip |
| CVE-2024-12797 | `cryptography` (PyPI) | Resolved by `cryptography>=46.0.5` pin |

## Reporting vulnerabilities

Open a [GitHub issue](../../issues) marked **Security**. Please do not disclose
vulnerabilities publicly before a fix is available. For sensitive reports, contact
the project maintainers through the GitHub security advisory system.
