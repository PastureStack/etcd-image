# syntax=docker/dockerfile:1.7
ARG UBUNTU_IMAGE=ubuntu:26.04@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03
ARG BUILDPLATFORM=linux/amd64

FROM --platform=${BUILDPLATFORM} ${UBUNTU_IMAGE} AS ca-trust
ADD --checksum=sha256:6077d27c6b6f8b23590cb01ff877ed8c804a67a5442cc32b5a33da10d2bd0e90 \
    https://snapshot.ubuntu.com/ubuntu/20260808T000000Z/pool/main/c/ca-certificates/ca-certificates_20260601~26.04.1_all.deb \
    /tmp/ca-certificates.deb
ADD --checksum=sha256:c1f53878bdada693da7fb64a28c06b7dd65a43b8452e6fcad670c0d09c77f293 \
    https://snapshot.ubuntu.com/ubuntu/20260808T000000Z/pool/main/o/openssl/openssl_3.5.5-1ubuntu3.3_amd64.deb \
    /tmp/openssl.deb
RUN set -eux; \
    dpkg -i /tmp/openssl.deb /tmp/ca-certificates.deb; \
    update-ca-certificates --fresh; \
    test -s /etc/ssl/certs/ca-certificates.crt; \
    test "$(openssl version | awk '{print $2}')" = 3.5.5; \
    rm -f /tmp/ca-certificates.deb /tmp/openssl.deb

FROM --platform=${BUILDPLATFORM} ${UBUNTU_IMAGE} AS source-base
ARG BUILDARCH=amd64
ARG GO_VERSION=1.26.5
ARG GO_LINUX_AMD64_SHA256=5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053
ARG GO_LINUX_ARM64_SHA256=fe4789e92b1f33358680864bbe8704289e7bb5fc207d80623c308935bd696d49
ARG GO_X_TEXT_VERSION=0.39.0
ARG GO_X_TEXT_SUM=UbZz4pLOvn600D6Oh6GGEI6VAmndrEBLv8/6BEXzyus=
ARG GO_X_TEXT_GO_MOD_SUM=3UwRclnC2g0TU9x8PZiyfOajCd1zaUNHF9cvqcQZ+ZM=
ARG GO_X_TEXT_LICENSE_SHA256=911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad
ARG UPSTREAM_REPOSITORY=etcd-io/etcd
ARG UPSTREAM_TAG=v3.7.1
ARG UPSTREAM_VERSION=3.7.1
ARG UPSTREAM_GO_VERSION=1.26.5
ARG UPSTREAM_INSECURE_TEST_KEY_SHA256=0db733264aec410f13fc95dc01c8c8956d870f7225c81e68d83a8035e0867d5a
ARG UPSTREAM_COMMIT=5e7fd0de9a57db03ecc11794dc40403a734c07bb
ARG UPSTREAM_ARCHIVE_SHA256=a9254be36198b8240fe1a5ea8018e67d9fdc148146888e7dec60c019ddc8870c
ARG SOURCE_DATE_EPOCH=1784835042

COPY package/ubuntu-apt.lock /tmp/ubuntu-apt.lock
COPY --from=ca-trust /etc/ca-certificates.conf /etc/ca-certificates.conf
COPY --from=ca-trust /etc/ssl/certs /etc/ssl/certs
COPY --from=ca-trust /usr/share/ca-certificates /usr/share/ca-certificates
ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    GOTELEMETRY=off \
    SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}
RUN set -eux; \
    . /tmp/ubuntu-apt.lock; \
    printf 'Types: deb\nURIs: https://snapshot.ubuntu.com/ubuntu/%s/\nSuites: %s %s-updates %s-backports %s-security\nComponents: main universe restricted multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
        "${UBUNTU_APT_SNAPSHOT}" "${UBUNTU_APT_SUITE}" "${UBUNTU_APT_SUITE}" \
        "${UBUNTU_APT_SUITE}" "${UBUNTU_APT_SUITE}" \
        > /etc/apt/sources.list.d/ubuntu.sources; \
    printf 'Acquire::https::CaInfo "/etc/ssl/certs/ca-certificates.crt";\n' \
        > /etc/apt/apt.conf.d/99pasturestack-ca; \
    rm -f /etc/apt/sources.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential="${UBUNTU_APT_BUILD_ESSENTIAL_VERSION}" \
        ca-certificates="${UBUNTU_APT_CA_CERTIFICATES_VERSION}" \
        curl="${UBUNTU_APT_CURL_VERSION}" \
        file="${UBUNTU_APT_FILE_VERSION}" \
        gcc="${UBUNTU_APT_GCC_VERSION}" \
        libc6-dev="${UBUNTU_APT_LIBC6_DEV_VERSION}" \
        tar="${UBUNTU_APT_TAR_VERSION}"; \
    rm -rf /var/lib/apt/lists/*; \
    case "${BUILDARCH}" in \
        amd64) go_arch=amd64; go_sha="${GO_LINUX_AMD64_SHA256}" ;; \
        arm64) go_arch=arm64; go_sha="${GO_LINUX_ARM64_SHA256}" ;; \
        *) echo "unsupported BUILDARCH=${BUILDARCH}" >&2; exit 1 ;; \
    esac; \
    curl --fail --silent --show-error --location --retry 5 --retry-all-errors \
        --output /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz"; \
    echo "${go_sha}  /tmp/go.tgz" | sha256sum -c -; \
    tar -xzf /tmp/go.tgz -C /usr/local; \
    rm -f /tmp/go.tgz; \
    test "$(go env GOVERSION)" = "go${GO_VERSION}"

RUN set -eux; \
    printf '%s\n' "${UPSTREAM_REPOSITORY}" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; \
    printf '%s\n' "${UPSTREAM_COMMIT}" | grep -Eq '^[0-9a-f]{40}$'; \
    printf '%s\n' "${UPSTREAM_ARCHIVE_SHA256}" | grep -Eq '^[0-9a-f]{64}$'; \
    curl --fail --silent --show-error --location --retry 5 --retry-all-errors \
        --output /tmp/etcd.tar.gz \
        "https://codeload.github.com/${UPSTREAM_REPOSITORY}/tar.gz/${UPSTREAM_COMMIT}"; \
    echo "${UPSTREAM_ARCHIVE_SHA256}  /tmp/etcd.tar.gz" | sha256sum -c -; \
    mkdir -p /src/etcd; \
    tar -xzf /tmp/etcd.tar.gz -C /src/etcd --strip-components=1; \
    rm -f /tmp/etcd.tar.gz; \
    test "$(cat /src/etcd/.go-version)" = "${UPSTREAM_GO_VERSION}"; \
    grep -Fq "Version           = \"${UPSTREAM_VERSION}\"" /src/etcd/api/version/version.go

RUN set -eux; \
    for module_dir in . api cache client/pkg client/v3 etcdctl etcdutl pkg server tests; do \
        if test ! -f "/src/etcd/${module_dir}/go.mod"; then \
            test "${module_dir}" = cache; \
            continue; \
        fi; \
        cd "/src/etcd/${module_dir}"; \
        go mod edit -require="golang.org/x/text@v${GO_X_TEXT_VERSION}"; \
        download_json="$(go mod download -json "golang.org/x/text@v${GO_X_TEXT_VERSION}")"; \
        printf '%s\n' "${download_json}" | grep -Fq '"Sum": "h1:'"${GO_X_TEXT_SUM}"'"'; \
        printf '%s\n' "${download_json}" | grep -Fq '"GoModSum": "h1:'"${GO_X_TEXT_GO_MOD_SUM}"'"'; \
        go mod verify; \
    done; \
    text_license="$(go env GOMODCACHE)/golang.org/x/text@v${GO_X_TEXT_VERSION}/LICENSE"; \
    echo "${GO_X_TEXT_LICENSE_SHA256}  ${text_license}" | sha256sum -c -; \
    install -D -m 0644 "${text_license}" /dependency-licenses/LICENSE.golang.org-x-text

COPY LICENSE ORIGIN.md COMPATIBILITY.md SECURITY.md LICENSE-STATUS.md package/upstream-source.lock /repo-docs/

FROM source-base AS etcd-test
WORKDIR /src/etcd
RUN set -eux; \
    test -z "$(gofmt -l api client pkg server etcdctl etcdutl)"; \
    go vet ./api/... ./client/pkg/... ./client/v3/... ./pkg/... ./server/storage/... ./server/etcdserver/... ./etcdctl/... ./etcdutl/...
RUN set -eux; \
    CGO_ENABLED=1 go test -race -count=1 -timeout=40m \
        ./api/... \
        ./client/pkg/... \
        ./client/v3/... \
        ./pkg/... \
        ./server/storage/... \
        ./server/etcdserver/...

FROM source-base AS etcd-builder-build
ARG TARGETARCH=amd64
ARG IMAGE_VERSION=3.7.2
ARG VERSION_PACKAGE_ROOT=go.etcd.io/etcd
ARG UPSTREAM_COMMIT=5e7fd0de9a57db03ecc11794dc40403a734c07bb
ARG SOURCE_DATE_EPOCH=1784835042
WORKDIR /src/etcd
RUN set -eux; \
    case "${TARGETARCH}" in amd64|arm64) ;; *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; esac; \
    printf '%s\n' "${IMAGE_VERSION}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; \
    go_ldflags="-s -w -buildid= -X ${VERSION_PACKAGE_ROOT}/api/v3/version.GitSHA=${UPSTREAM_COMMIT} -X ${VERSION_PACKAGE_ROOT}/api/v3/version.Version=${IMAGE_VERSION}"; \
    for pass in first second; do \
        mkdir -p "/tmp/${pass}"; \
        (cd server && CGO_ENABLED=0 GOOS=linux GOARCH="${TARGETARCH}" go build -p=2 -buildvcs=false -mod=readonly -trimpath -ldflags="${go_ldflags}" -o "/tmp/${pass}/etcd" .); \
        (cd etcdctl && CGO_ENABLED=0 GOOS=linux GOARCH="${TARGETARCH}" go build -p=2 -buildvcs=false -mod=readonly -trimpath -ldflags="${go_ldflags}" -o "/tmp/${pass}/etcdctl" .); \
        (cd etcdutl && CGO_ENABLED=0 GOOS=linux GOARCH="${TARGETARCH}" go build -p=2 -buildvcs=false -mod=readonly -trimpath -ldflags="${go_ldflags}" -o "/tmp/${pass}/etcdutl" .); \
    done; \
    cmp /tmp/first/etcd /tmp/second/etcd; \
    cmp /tmp/first/etcdctl /tmp/second/etcdctl; \
    cmp /tmp/first/etcdutl /tmp/second/etcdutl; \
    echo "${UPSTREAM_INSECURE_TEST_KEY_SHA256}  /src/etcd/pkg/proxy/fixtures/server.key.insecure" | sha256sum -c -; \
    rm -f /src/etcd/pkg/proxy/fixtures/server.key.insecure; \
    test ! -e /src/etcd/pkg/proxy/fixtures/server.key.insecure; \
    install -d -m 0755 /image-root/usr/share/doc/pasturestack-etcd-image; \
    for binary in etcd etcdctl etcdutl; do \
        file "/tmp/first/${binary}" | grep -q 'statically linked'; \
        install -D -m 0755 "/tmp/first/${binary}" "/image-root/usr/local/bin/${binary}"; \
        go version -m "/tmp/first/${binary}" > "/image-root/usr/share/doc/pasturestack-etcd-image/${binary}.go-buildinfo.txt"; \
    done; \
    install -D -m 0644 /src/etcd/LICENSE /image-root/usr/share/licenses/pasturestack-etcd-image/LICENSE.etcd-upstream; \
    install -D -m 0644 /src/etcd/bill-of-materials.json /image-root/usr/share/licenses/pasturestack-etcd-image/ETCD-UPSTREAM-BILL-OF-MATERIALS.json; \
    install -D -m 0644 /src/etcd/bill-of-materials.override.json /image-root/usr/share/licenses/pasturestack-etcd-image/ETCD-UPSTREAM-BILL-OF-MATERIALS-OVERRIDE.json; \
    install -D -m 0644 /dependency-licenses/LICENSE.golang.org-x-text /image-root/usr/share/licenses/pasturestack-etcd-image/LICENSE.golang.org-x-text; \
    install -D -m 0644 /repo-docs/LICENSE /image-root/usr/share/licenses/pasturestack-etcd-image/LICENSE.repository-original; \
    install -D -m 0644 /repo-docs/LICENSE-STATUS.md /image-root/usr/share/licenses/pasturestack-etcd-image/LICENSE-STATUS.md; \
    install -D -m 0644 /repo-docs/ORIGIN.md /image-root/usr/share/doc/pasturestack-etcd-image/ORIGIN.md; \
    install -D -m 0644 /repo-docs/COMPATIBILITY.md /image-root/usr/share/doc/pasturestack-etcd-image/COMPATIBILITY.md; \
    install -D -m 0644 /repo-docs/SECURITY.md /image-root/usr/share/doc/pasturestack-etcd-image/SECURITY.md; \
    install -D -m 0644 /repo-docs/upstream-source.lock /image-root/usr/share/doc/pasturestack-etcd-image/upstream-source.lock; \
    install -d -m 0700 /image-root/var/lib/etcd; \
    chown 65532:65532 /image-root/var/lib/etcd; \
    find /image-root -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +; \
    if test "${TARGETARCH}" = "$(go env GOARCH)"; then \
        /image-root/usr/local/bin/etcd --version | grep -F "etcd Version: ${IMAGE_VERSION}"; \
        /image-root/usr/local/bin/etcdctl version | grep -F "etcdctl version: ${IMAGE_VERSION}"; \
        /image-root/usr/local/bin/etcdutl version | grep -F "etcdutl version: ${IMAGE_VERSION}"; \
    fi

FROM scratch AS etcd-builder
COPY --from=etcd-builder-build / /
CMD ["/bin/true"]

FROM scratch
ARG IMAGE_VERSION=3.7.2
ARG SOURCE_REVISION=unknown
ARG UPSTREAM_TAG=v3.7.1
ARG UPSTREAM_VERSION=3.7.1
ARG UPSTREAM_COMMIT=5e7fd0de9a57db03ecc11794dc40403a734c07bb
ARG GO_X_TEXT_VERSION=0.39.0
LABEL org.opencontainers.image.source="https://github.com/PastureStack/etcd-image" \
      org.opencontainers.image.title="PastureStack etcd image" \
      org.opencontainers.image.description="Maintained etcd image for reviewed compatibility migration" \
      org.opencontainers.image.vendor="PastureStack" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      io.pasturestack.upstream.tag="${UPSTREAM_TAG}" \
      io.pasturestack.upstream.version="${UPSTREAM_VERSION}" \
      io.pasturestack.upstream.commit="${UPSTREAM_COMMIT}" \
      io.pasturestack.dependency.golang-x-text="v${GO_X_TEXT_VERSION}" \
      io.pasturestack.ubuntu.snapshot="20260808T000000Z"
COPY --from=etcd-builder /image-root/ /
WORKDIR /var/lib/etcd
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/etcd"]
