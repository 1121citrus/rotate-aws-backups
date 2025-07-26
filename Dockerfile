# syntax=docker/dockerfile:1

FROM 1121citrus/ha-bash-base:latest

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

