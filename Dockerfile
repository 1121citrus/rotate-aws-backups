# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.12.10
ARG ALPINE_VERSION=3.21
ARG AWSCLI_VERSION=2.26.5

FROM python:${PYTHON_VERSION}-alpine${ALPINE_VERSION}

ARG PYTHON_VERSION
ENV PYTHON_VERSION=${PYTHON_VERSION}

ARG ALPINE_VERSION
ENV ALPINE_VERSION=${ALPINE_VERSION}

ARG AWSCLI_VERSION
ENV AWSCLI_VERSION=${AWSCLI_VERSION}

RUN APK_PACKAGES=aws-cli \
    && echo [INFO] start installing rotate-backups command \
    && echo [INFO] installing apk packages: ${APK_PACKAGES} \
    && apk update \
    && apk add --no-cache ${APK_PACKAGES} \
    && echo [INFO] completed installing apk packages ... \
    && echo [INFO] installing pip packages: rotate-backups \
    && python3 -m ensurepip \
    && pip3 install --no-cache --upgrade pip rotate-backups \
    && mkdir -pv /usr/local/include/1121citrus \
    && echo [INFO] completed installing rotate-backups package

COPY --chmod=755 ./src/rotate ./src/rotate-aws-backups ./src/setup-rotate-backups /usr/local/bin/
COPY --chmod=644 ./src/common-functions /usr/local/include/1121citrus/common-functions

WORKDIR /
ENTRYPOINT [ "/bin/sh", "-c" ]
CMD [ "/usr/local/bin/setup-rotate-backups" ]

