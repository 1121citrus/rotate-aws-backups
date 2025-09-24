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

ARG HA_BASH_BASE_TAG=1.0.0
FROM 1121citrus/ha-bash-base:${HA_BASH_BASE_TAG}

RUN apk add python3 py3-pip

RUN APK_PACKAGES="aws-cli python3 py3-pip pipx" \
    && echo [INFO] start installing rotate-backups command \
    && echo [INFO] installing apk packages: ${APK_PACKAGES} \
    && apk update \
    && apk add --no-cache ${APK_PACKAGES} \
    && echo [INFO] completed installing apk packages ... \
    && echo [INFO] installing pip packages: rotate-backups \
    && pipx ensurepath \
    && pipx install --global rotate-backups \
    && mkdir -m 755 -p -v /usr/local/include/1121citrus /var/log/rotate-aws-backups \
    && touch /var/log/rotate-aws-backups/rotate-backups.logA \
    && echo [INFO] completed installing rotate-backups package

COPY --chmod=755  ./src/healthcheck ./src/rotate ./src/rotate-aws-backups ./src/startup /usr/local/bin/

# HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD /usr/local/bin/healthcheck

WORKDIR /
ENTRYPOINT [ "/bin/sh", "-c" ]
CMD [ "/usr/local/bin/startup" ]

