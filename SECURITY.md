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

**Trivy gate status (as of 2026-10-29): PASS.** Trivy is the CI gating
scanner and fails builds on unfixed HIGH/CRITICAL findings, except CVEs
explicitly listed in `.trivyignore` after security review. Five entries are
currently in force (see table below).

### Scanner reconciliation on current image

Image analyzed: `rotate-aws-backups:dev-248d306` (rebuilt locally, uncached,
supercronic builder bumped to `golang:1.27.3-alpine`).

- Trivy (gating, HIGH/CRITICAL, ignore-unfixed): `0C / 0H`.
- Grype (full severity): `0C / 0H / 13M` — all 13 Medium findings have no
  available upstream fix (see table below). Prior to the 2026-10-28
  supercronic builder bump, Grype also reported 1 Critical, 23 High, and 6
  additional Medium `stdlib` go-module findings against the `go1.27.0`
  binary; all are now resolved.
- Docker Scout (advisory): not re-run this session — the local sandbox
  blocked its outbound call to Docker's cloud scanning backend as a
  "create public surface" action. CI reproduces this reconciliation on
  every push.

### Unfixable findings (current)

| Scanner | Package | CVE | Severity | Fix status | Notes |
| --- | --- | --- | --- | --- | --- |
| Trivy (suppressed, `.trivyignore`) | `msgpack 1.1.2` | GHSA-6v7p-g79w-8964, CVE-2026-114613 | HIGH | Fixed upstream (1.2.3 on pip `main`) | Vendored inside `pip`'s own `_vendor/msgpack` bundle (embedded in CPython's `ensurepip/_bundled` wheel), not this project's dependency. `pip` 26.2.2 (current PyPI release) still vendors `msgpack==1.1.2`. |
| Trivy (suppressed, `.trivyignore`) | `urllib3 2.7.0` | CVE-2026-97687, CVE-2026-97689 | HIGH | Not yet fixed upstream (pip `main` still pins 2.7.0) | Same vendoring mechanism: `pip`'s internal `_vendor/urllib3` bundle, not this project's `urllib3>=2.7.0` floor (already current — the standalone install resolves to 2.8.0). Unlike `msgpack`, even pip's `main`-branch `vendor.txt` has not moved past 2.7.0, so no fix exists anywhere upstream yet. |
| Trivy (suppressed, `.trivyignore`) | `setuptools 70.3.0` | CVE-2025-47273 | HIGH | Fixed upstream (78.1.1) | Same as above: `pip`'s internal vendored copy, not this project's `setuptools>=84.0.0` floor (already current). `pypa/pip`'s `main`-branch `vendor.txt` deliberately still pins `setuptools==70.3.0` for internal bootstrapping. |
| Grype | `python 3.14.10` | CVE-2025-15367 | MEDIUM | 3.15.0a6 | Fix target is a Python 3.15 alpha prerelease; not deployed in any stable Alpine base. |
| Grype | `python 3.14.10` | CVE-2026-12345 | MEDIUM | 3.15.0rc3 | Fix target is a Python 3.15 release candidate; not deployed in any stable Alpine base. |
| Grype | `coreutils`, `coreutils-env`, `coreutils-fmt`, `coreutils-sha512sum 9.8-r1` | CVE-2016-2781, CVE-2026-56391 | MEDIUM | None | No Alpine secfix entry exists for either CVE against `coreutils` on any branch (checked `secdb.alpinelinux.org/v3.23/main.json`, 2026-10-28); already at Alpine 3.23's latest packaged version. |
| Grype | `busybox`, `busybox-binsh`, `ssl_client 1.37.0-r30` | CVE-2025-60876 | MEDIUM | None | No Alpine secfix entry exists; already at Alpine 3.23's latest packaged version. |

### Advisory medium/low findings

All current advisory findings are captured in the table above; none have an
available upstream fix. Re-review alongside the next scheduled CVE pass or
whenever Alpine, CPython, or pip ship a fix.

---

### Remediation history

| CVE | Package | Fix applied |
| --- | --- | --- |
| CVE-2026-21441, CVE-2025-66471, CVE-2025-66418, CVE-2025-50181 | `urllib3` (PyPI) | Pinned `urllib3>=2.6.3` in Python 3.14 env |
| CVE-2026-44431, + above | `urllib3` (PyPI) | Raised floor to `urllib3>=2.7.0` (2026-05-14) |
| CVE-2026-26007 | `cryptography` (PyPI) | Pinned `cryptography>=46.0.5` in Python 3.14 env |
| multiple | `cryptography` (PyPI) | Raised floor to `cryptography>=48.0.0` (2026-05-14) |
| CVE-2024-3651 | `idna` (PyPI) | Pinned `idna>=3.7`; raised to `idna>=3.15` (2026-05-14), then `idna>=3.16` (2026-05-23) |
| CVE-2024-5569 | `zipp` (PyPI) | Pinned `zipp>=3.19.1`; raised to `zipp>=4.1.0` (2026-05-23) |
| CVE-2024-53427, CVE-2025-48060, CVE-2024-23337 | `jq` (APK) | Base image bump to `python:3.14-alpine3.22` |
| multiple | base OS packages | Base image bump to `python:3.14-alpine3.23` (2026-06-08) |
| CVE-2025-8869, CVE-2026-1703 | `pip` (system Python) | Upgraded system Python pip to ≥26.0 |
| CVE-2024-12797 | `cryptography` (PyPI) | Resolved by `cryptography>=46.0.5` pin |
| CVE-2024-6345 | `setuptools` (PyPI) | Pinned `setuptools>=78.1.0` in both Python envs |
| CVE-2026-32280, CVE-2026-32282, CVE-2026-33810 | `supercronic` Go stdlib | Built supercronic from source with `golang:1.26.2-alpine` |
| CVE-2026-33811, CVE-2026-33814, CVE-2026-39820, CVE-2026-39836, CVE-2026-42499 | `supercronic` Go stdlib | Upgraded builder to `golang:1.26.3-alpine` (2026-05-14) |
| CVE-2026-25679, CVE-2026-27140, CVE-2026-32280, CVE-2026-32281, CVE-2026-32283, CVE-2026-27143, CVE-2025-68121, CVE-2026-33811, CVE-2026-33814, CVE-2026-39820, CVE-2026-39836, CVE-2026-42499 | `gojq` (APK, Go stdlib exposure) | Removed `gojq` dependency; switched to native `jq` package (2026-06-08) |
| CVE-2026-42504 | `supercronic` Go stdlib | Rebuilt current image and verified scanner results on rebuilt `latest` to eliminate stale image-layer finding (2026-06-08) |
| CVE-2026-39822 | `supercronic` Go stdlib | Upgraded builder to `golang:1.26.5-alpine` (2026-07-12) |
| multiple | `cryptography` (PyPI) | Raised floor to `cryptography>=48.0.1` (2026-06-10) |
| CVE-2026-34182 (CRITICAL), CVE-2026-45447, CVE-2026-7383, CVE-2026-9076, CVE-2026-45445, CVE-2026-42764, CVE-2026-34183, CVE-2026-34180 | `openssl` (APK) | APK upgrade to `openssl 3.5.7-r0` via image rebuild (2026-06-10) |
| CVE-2026-32280, CVE-2026-32282, CVE-2026-33810, CVE-2026-33811, CVE-2026-33814, CVE-2026-39820, CVE-2026-39836, CVE-2026-42499 | `supercronic` Go stdlib | Upgraded builder to `golang:1.27.0-alpine` (2026-09-02, Dependabot #31) |
| CVE-2026-39821, CVE-2026-56862, CVE-2026-56859, CVE-2026-56853, CVE-2026-46600, CVE-2026-33818, CVE-2026-56858, CVE-2026-56860 | `stdlib` (Go, via `supercronic`) | Same `golang:1.27.0-alpine` bump; superseded by the v0.2.49 supercronic rebuild below |
| CVE-2026-39824 | `golang.org/x/sys` (Go, via `supercronic`) | Bumped `SUPERCRONIC_VERSION` from v0.2.45 to v0.2.49, dropping the vulnerable transitive dependency (2026-09-02) |
| CVE-2026-13346 | `pip` (system Python) | Raised floor to `pip>=26.2.0` (2026-09-02) |
| CVE-2026-63073, CVE-2026-75803, CVE-2026-63076, CVE-2026-63075, CVE-2026-63072, CVE-2026-54874, CVE-2026-18798, CVE-2026-14457, CVE-2026-14456, CVE-2026-63074 | `openssl` (APK) | Resolved by rebuilding against Alpine 3.23's current package feed (`openssl 3.5.8-r0`); no Dockerfile change needed (2026-09-02) |
| CVE-2026-32316 | `jq` (APK) | Resolved by rebuilding against Alpine 3.23's current package feed (`jq 1.8.2-r0`); removed stale `.trivyignore` entry (2026-09-02) |
| CVE-2026-11822, CVE-2026-11824 | `sqlite` (APK) | Resolved by rebuilding against Alpine 3.23's current package feed (`sqlite 3.53.4-r0`); removed stale `.trivyignore` entries (2026-09-02) |
| CVE-2026-69247 | `cryptography` (PyPI) | Raised floor to `cryptography>=50.0.1` (2026-09-02, Dependabot #32) |
| CVE-2026-32316 (transitively via `idna`) | `idna` (PyPI) | Raised floor to `idna>=3.19` (2026-09-02, Dependabot #30) |
| CVE-2026-59890 | `setuptools` (PyPI, project floor) | Raised floor to `setuptools>=84.0.0` (2026-09-02, Dependabot #28) |
| CVE-2026-78663, GO-2026-6612, GO-2026-6604, CVE-2026-78659, GO-2026-6603, CVE-2026-78669, GO-2026-6611, CVE-2026-97031, GO-2026-6607, CVE-2026-94440, GO-2026-6608, CVE-2026-97032, GO-2026-6617, CVE-2026-78667, GO-2026-6609, CVE-2026-56866, GO-2026-6605, CVE-2026-78660, GO-2026-6610, CVE-2026-94439, GO-2026-6613, CVE-2026-94448, CVE-2026-97030, GO-2026-6599, GO-2026-6600, CVE-2026-94447, CVE-2026-94444, CVE-2026-111943, GO-2026-6809 | `stdlib` (Go, via `supercronic`) | Upgraded `supercronic` builder from `golang:1.27.0-alpine` to `golang:1.27.3-alpine`; pinned `ENV GOTOOLCHAIN=local` in the builder stage to prevent a silent toolchain auto-download from defeating the pin (2026-10-28) |

## Reporting vulnerabilities

Please report security vulnerabilities through the [GitHub Security tab](https://github.com/1121citrus/rotate-aws-backups/security).
Do not open a public GitHub issue for security vulnerabilities.
