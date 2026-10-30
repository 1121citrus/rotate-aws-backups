# syntax=docker/dockerfile:1

# Yet another version of `rotate-backups` but this time applied to an AWS S3 backup archive bucket.
# Copyright (C) 2025 James Hanlon [mailto:jim@hanlonsoftware.com]
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

ARG ROTATE_BACKUPS_VERSION=
ARG VERSION=dev
# renovate: datasource=github-releases depName=aptible/supercronic
ARG SUPERCRONIC_VERSION=v0.2.49

# ── Supercronic build stage ────────────────────────────────────────────────
# Builds supercronic from source with the golang:1.27.3-alpine toolchain,
# which patches (Grype, 2026-10-28):
#   CVE-2026-78663 (net/http request smuggling) CRITICAL
#   CVE-2026-78659, CVE-2026-78669, CVE-2026-97031, CVE-2026-94440,
#   CVE-2026-97032, CVE-2026-78667, CVE-2026-56866, CVE-2026-78660,
#   CVE-2026-94439, CVE-2026-94447, CVE-2026-94444 HIGH
#   CVE-2026-94448, CVE-2026-97030 MEDIUM
#   CVE-2026-111943 (go1.27.3-only fix) UNKNOWN
# GOTOOLCHAIN=local forces the build to use the Go version shipped in the
# builder image above rather than silently auto-downloading whatever
# toolchain supercronic's go.mod requests, which would defeat the pin
# (see aws-backup-base's 2026-10-28 remediation of the same failure mode).
# Remove this stage and restore the wget installation once an upstream
# supercronic release ships with Go >= 1.26.3 (or >= 1.25.10).
FROM golang:1.27.3-alpine AS supercronic-builder
ARG SUPERCRONIC_VERSION
ENV GOTOOLCHAIN=local
RUN CGO_ENABLED=0 go install github.com/aptible/supercronic@${SUPERCRONIC_VERSION}

# The literal tag lets Dependabot open PRs when a newer python:X.Y.Z-alpineX.Y
# is published.  The python and Alpine minor versions are pinned together so
# the OS package set is fully reproducible and bumps are deliberate changes.
FROM python:3.14-alpine3.23

# Expose base-image versions as environment variables for runtime inspection.
ENV PYTHON_VERSION=3.14
ENV ALPINE_VERSION=3.23

ARG ROTATE_BACKUPS_VERSION
ENV ROTATE_BACKUPS_VERSION=${ROTATE_BACKUPS_VERSION}

ARG SUPERCRONIC_VERSION

ARG VERSION
ENV ROTATE_AWS_BACKUPS_VERSION=${VERSION}
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown

# OCI image annotation labels (https://github.com/opencontainers/image-spec/blob/main/annotations.md).
# These are embedded in the image manifest and surfaced by 'docker inspect',
# 'docker scout', and supply-chain tooling (Syft, Grype, cosign, etc.).
LABEL org.opencontainers.image.title="rotate-aws-backups" \
      org.opencontainers.image.description="Scheduled rotation of AWS S3 backup objects using the rotate-backups retention policy engine." \
      org.opencontainers.image.url="https://github.com/1121citrus/rotate-aws-backups" \
      org.opencontainers.image.source="https://github.com/1121citrus/rotate-aws-backups" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Install supercronic binary compiled with Go 1.27.3 (patches the Go stdlib
# CVEs listed on the builder stage above).
COPY --from=supercronic-builder --chmod=755 /go/bin/supercronic /usr/local/bin/

COPY requirements.txt /tmp/
# hadolint ignore=DL3013,DL3018,DL3020,DL4006
RUN echo "[INFO] start installing rotate-aws-backups" \
        && apk update \
        && apk upgrade --no-cache --no-interactive \
        && apk add --no-cache \
               'bash>5' \
               'coreutils>9' \
               'jq' \
        && echo "[INFO] upgrading pip" \
        && pip install --no-cache-dir --upgrade pip \
        && pip install --no-cache-dir awscli \
        && echo "[INFO] installing rotate-backups (pip)" \
        && if [ -n "${ROTATE_BACKUPS_VERSION}" ]; then \
               pip install --no-cache-dir "rotate-backups==${ROTATE_BACKUPS_VERSION}"; \
           else \
               pip install --no-cache-dir rotate-backups; \
           fi \
        && echo "[INFO] patching vulnerable transitive dependencies" \
        && pip install --no-cache-dir -r /tmp/requirements.txt \
        && echo "[INFO] creating pipes compatibility shim for Python 3.13" \
        && python3 -c \
               "import site; \
                open(site.getsitepackages()[0]+'/pipes.py','w') \
                    .write('# pipes was removed in Python 3.13; shlex.quote is the replacement.\nfrom shlex import quote\n')" \
        && rm -f /usr/lib/python${PYTHON_VERSION}/EXTERNALLY-MANAGED \
       && python3 -m ensurepip --upgrade \
       && python3 -m pip install --no-cache-dir "pip>=26.2.0" \
       && python3 -m pip install --no-cache-dir \
               -r /tmp/requirements.txt \
        && rm /tmp/requirements.txt \
        && install -d -m 755 \
               /usr/local/include \
               /usr/local/share/rotate-aws-backups \
               /var/log/rotate-aws-backups \
        && touch /var/log/rotate-aws-backups/rotate-backups.log \
        && printf '%s\n' "${VERSION}" \
               > /usr/local/share/rotate-aws-backups/version \
        && echo "[INFO] completed installing rotate-aws-backups"

# Create a non-privileged user; grant ownership of runtime-writable paths.
ARG UID=10001
RUN adduser \
        --disabled-password --gecos "" --shell "/sbin/nologin" \
        --uid "${UID}" rotate-aws-backups \
    && rm -f /var/spool/cron/crontabs \
    && install -d -m 0755 -o rotate-aws-backups /var/spool/cron/crontabs \
    && chown rotate-aws-backups \
           /var/log/rotate-aws-backups \
           /var/log/rotate-aws-backups/rotate-backups.log

COPY --chmod=644 ./include/common-functions /usr/local/include/
COPY --chmod=755  ./src/healthcheck ./src/rotate ./src/rotate-aws-backups \
                  ./src/startup /usr/local/bin/

USER rotate-aws-backups

HEALTHCHECK --interval=60s --timeout=5s --retries=3 CMD ["/usr/local/bin/healthcheck"]

WORKDIR /

ENTRYPOINT ["/usr/local/bin/rotate-aws-backups"]
