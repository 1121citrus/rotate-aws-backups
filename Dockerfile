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

ARG PYTHON_VERSION=3.12
ARG ALPINE_VERSION=3.22
ARG ROTATE_BACKUPS_VERSION=
ARG VERSION=dev

FROM python:${PYTHON_VERSION}-alpine${ALPINE_VERSION}

# Re-declare build args after FROM so they are visible in the build stage.
ARG PYTHON_VERSION
ENV PYTHON_VERSION=${PYTHON_VERSION}

ARG ALPINE_VERSION
ENV ALPINE_VERSION=${ALPINE_VERSION}

ARG ROTATE_BACKUPS_VERSION
ENV ROTATE_BACKUPS_VERSION=${ROTATE_BACKUPS_VERSION}

ARG VERSION
ENV ROTATE_AWS_BACKUPS_VERSION=${VERSION}

# OCI image annotation labels (https://github.com/opencontainers/image-spec/blob/main/annotations.md).
# These are embedded in the image manifest and surfaced by 'docker inspect',
# 'docker scout', and supply-chain tooling (Syft, Grype, cosign, etc.).
LABEL org.opencontainers.image.title="rotate-aws-backups" \
      org.opencontainers.image.description="Scheduled rotation of AWS S3 backup objects using the rotate-backups retention policy engine." \
      org.opencontainers.image.url="https://github.com/1121citrus/rotate-aws-backups" \
      org.opencontainers.image.source="https://github.com/1121citrus/rotate-aws-backups" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"

# hadolint ignore=DL3013,DL3018
RUN echo "[INFO] start installing rotate-aws-backups" \
        && apk update \
        && apk upgrade --no-cache --no-interactive \
        && apk add --no-cache \
               'aws-cli>2' \
               'bash>5' \
               'coreutils>9' \
               'jq>1' \
        && echo "[INFO] upgrading pip" \
        && pip install --no-cache-dir --upgrade pip \
        && echo "[INFO] installing rotate-backups (pip)" \
        && if [ -n "${ROTATE_BACKUPS_VERSION}" ]; then \
               pip install --no-cache-dir "rotate-backups==${ROTATE_BACKUPS_VERSION}"; \
           else \
               pip install --no-cache-dir rotate-backups; \
           fi \
        && echo "[INFO] patching vulnerable transitive dependencies" \
        && pip install --no-cache-dir \
               "urllib3>=2.6.3" \
               "cryptography>=46.0.5" \
               "zipp>=3.19.1" \
        && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED \
        && /usr/bin/python3 -m ensurepip --upgrade \
        && /usr/bin/python3 -m pip install --no-cache-dir "pip>=26.0" \
        && /usr/bin/python3 -m pip install --no-cache-dir \
               "urllib3>=2.6.3" \
               "cryptography>=46.0.5" \
               "zipp>=3.19.1" \
        && install -d -m 755 \
               /usr/local/include \
               /usr/local/share/rotate-aws-backups \
               /var/log/rotate-aws-backups \
        && touch /var/log/rotate-aws-backups/rotate-backups.log \
        && printf '%s\n' "${VERSION}" \
               > /usr/local/share/rotate-aws-backups/version \
        && echo "[INFO] completed installing rotate-aws-backups"

COPY --chmod=644 ./src/include/common-functions /usr/local/include/
COPY --chmod=755  ./src/healthcheck ./src/rotate ./src/rotate-aws-backups \
                  ./src/startup /usr/local/bin/

HEALTHCHECK --interval=60s --timeout=5s --retries=3 CMD ["/usr/local/bin/healthcheck"]

WORKDIR /

# NOTE: The container runs as root.  Alpine's busybox crond manages per-user
# crontabs under /var/spool/cron/crontabs/{user}; running as root is the
# straightforward way to write and read that file without additional privilege
# setup.  Constrain the blast-radius at the Docker/Compose layer instead:
#   - mount the aws-config credential file read-only via a Docker secret
#   - do not bind-mount the host filesystem into the container
#   - run the container in a network-isolated environment with only outbound
#     access to AWS S3 endpoints
ENTRYPOINT ["/usr/local/bin/rotate-aws-backups"]
