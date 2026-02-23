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
ARG ALPINE_VERSION=3.21
ARG ROTATE_BACKUPS_VERSION=

FROM python:${PYTHON_VERSION}-alpine${ALPINE_VERSION}

ARG PYTHON_VERSION
ENV PYTHON_VERSION=${PYTHON_VERSION}

ARG ALPINE_VERSION
ENV ALPINE_VERSION=${ALPINE_VERSION}

RUN APK_PACKAGES="aws-cli bash coreutils jq" \
        && echo [INFO] start installing rotate-aws-backups \
        && echo [INFO] installing apk packages: ${APK_PACKAGES} \
        && apk update \
        && apk upgrade --no-cache --no-interactive \
        && apk add --no-cache ${APK_PACKAGES} \
        && echo [INFO] completed installing apk packages ... \
        && echo [INFO] upgrading pip \
        && pip install --no-cache-dir --upgrade pip \
        && echo "[INFO] installing rotate-backups (pip)" \
        && if [ -n "${ROTATE_BACKUPS_VERSION}" ]; then \
                 pip install --no-cache-dir "rotate-backups==${ROTATE_BACKUPS_VERSION}"; \
             else \
                 pip install --no-cache-dir rotate-backups; \
             fi \
        && mkdir -m 755 -p -v /usr/local/include /var/log/rotate-aws-backups \
        && touch /var/log/rotate-aws-backups/rotate-backups.log \
        && echo [INFO] completed installing rotate-aws-backups

COPY --chmod=644 ./src/include/common-functions /usr/local/include/
COPY --chmod=755  ./src/healthcheck ./src/rotate ./src/rotate-aws-backups ./src/startup /usr/local/bin/

HEALTHCHECK --interval=60s --timeout=5s --retries=3 CMD ["/usr/local/bin/healthcheck"]

WORKDIR /
ENTRYPOINT ["/usr/local/bin/startup"]

