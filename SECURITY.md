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

The container runs as the dedicated `rotate-aws-backups` user (UID 10001,
shell `/sbin/nologin`).  The crontab is written to
`/var/spool/cron/crontabs/rotate-aws-backups`; busybox `crond` reads it
as that user.

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

**Trivy gate status (as of 2026-05-14): PASS — no unfixed HIGH/CRITICAL CVEs.**
Trivy scans every CI build and fails on any unfixed HIGH/CRITICAL finding.
The items below are reported by Grype and Docker Scout (advisory only) and do
not block the pipeline.

**Distinction:** A "fixable" CVE has a patch available but not yet deployed.
An "unfixed" CVE has no patch available from any vendor.

### Advisory-only findings (Grype / Docker Scout)

#### Alpine APK packages — no upstream fix available

| CVE | Package | Severity | Notes |
| --- | --- | --- | --- |
| CVE-2016-2781 | `coreutils 9.7-r1` | MEDIUM | Affects `chroot`; `chroot` is not used in this container. No upstream fix ever. |
| CVE-2025-60876 | `busybox 1.37.0-r20` | MEDIUM | No Alpine fix available. |
| CVE-2025-70873 | `sqlite-libs 3.49.2-r1` | HIGH | No Alpine fix available. |

#### `gojq` (apk) — embedded Go stdlib compiled with go1.24.12

The Alpine `gojq` package is compiled with Go 1.24.12; the fix requires a
new Alpine package built with Go ≥ 1.25.10 / ≥ 1.26.3.
`gojq` does not accept network input in this container, limiting exposure.

| CVE | Severity | Fixed in Go |
| --- | --- | --- |
| CVE-2026-25679 | HIGH | ≥ 1.25.8 / ≥ 1.26.1 |
| CVE-2026-27140 | HIGH | ≥ 1.25.9 / ≥ 1.26.2 |
| CVE-2026-32280 | HIGH | ≥ 1.25.9 / ≥ 1.26.2 |
| CVE-2026-32281 | HIGH | ≥ 1.25.9 / ≥ 1.26.2 |
| CVE-2026-32283 | HIGH | ≥ 1.25.9 / ≥ 1.26.2 |
| CVE-2026-27143 | CRITICAL | ≥ 1.25.9 / ≥ 1.26.2 |
| CVE-2025-68121 | CRITICAL | ≥ 1.24.13 / ≥ 1.25.7 |
| CVE-2026-33811 | HIGH | ≥ 1.25.10 / ≥ 1.26.3 |
| CVE-2026-33814 | HIGH | ≥ 1.25.10 / ≥ 1.26.3 |
| CVE-2026-39820 | HIGH | ≥ 1.25.10 / ≥ 1.26.3 |
| CVE-2026-39836 | HIGH | ≥ 1.25.10 / ≥ 1.26.3 |
| CVE-2026-42499 | HIGH | ≥ 1.25.10 / ≥ 1.26.3 |

#### Python 3.14 binary — no fix in Alpine yet

| CVE | Severity | Notes |
| --- | --- | --- |
| CVE-2026-6100 | CRITICAL | Use-after-free in decompression; no Alpine fix available. |
| CVE-2026-3298 | HIGH | No Alpine fix available. |
| CVE-2026-4786 | HIGH | `webbrowser.open()` command injection; `webbrowser` is not used in this container. |

---

### Remediation history

| CVE | Package | Fix applied |
| --- | --- | --- |
| CVE-2026-21441, CVE-2025-66471, CVE-2025-66418, CVE-2025-50181 | `urllib3` (PyPI) | Pinned `urllib3>=2.6.3` in Python 3.14 env |
| CVE-2026-44431, + above | `urllib3` (PyPI) | Raised floor to `urllib3>=2.7.0` (2026-05-14) |
| CVE-2026-26007 | `cryptography` (PyPI) | Pinned `cryptography>=46.0.5` in Python 3.14 env |
| multiple | `cryptography` (PyPI) | Raised floor to `cryptography>=48.0.0` (2026-05-14) |
| CVE-2024-3651 | `idna` (PyPI) | Pinned `idna>=3.7`; raised to `idna>=3.15` (2026-05-14) |
| CVE-2024-5569 | `zipp` (PyPI) | Pinned `zipp>=3.19.1` |
| CVE-2024-53427, CVE-2025-48060, CVE-2024-23337 | `jq` (APK) | Base image bump to `python:3.14-alpine3.22` |
| CVE-2025-8869, CVE-2026-1703 | `pip` (system Python) | Upgraded system Python pip to ≥26.0 |
| CVE-2024-12797 | `cryptography` (PyPI) | Resolved by `cryptography>=46.0.5` pin |
| CVE-2024-6345 | `setuptools` (PyPI) | Pinned `setuptools>=78.1.0` in both Python envs |
| CVE-2026-32280, CVE-2026-32282, CVE-2026-33810 | `supercronic` Go stdlib | Built supercronic from source with `golang:1.26.2-alpine` |
| CVE-2026-33811, CVE-2026-33814, CVE-2026-39820, CVE-2026-39836, CVE-2026-42499 | `supercronic` Go stdlib | Upgraded builder to `golang:1.26.3-alpine` (2026-05-14) |

## Reporting vulnerabilities

Please report security vulnerabilities through the [GitHub Security tab](https://github.com/1121citrus/rotate-aws-backups/security).
Do not open a public GitHub issue for security vulnerabilities.
