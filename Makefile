include package/upstream-source.lock

SEVERITIES ?= HIGH,CRITICAL
VERSION ?= 3.7.2
IMAGE_REPOSITORY ?= pasturestack/etcd-image
IMAGE_TAG ?= v$(VERSION)
IMAGE ?= $(IMAGE_REPOSITORY):$(IMAGE_TAG)
SOURCE_REVISION ?= $(shell git rev-parse HEAD)

UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
HOST_PLATFORM := linux/amd64
HOST_ARCH := amd64
else ifeq ($(UNAME_M),aarch64)
HOST_PLATFORM := linux/arm64
HOST_ARCH := arm64
else
HOST_PLATFORM := linux/$(UNAME_M)
HOST_ARCH := $(UNAME_M)
endif

BUILD_PLATFORM ?= $(HOST_PLATFORM)
BUILD_ARCH ?= $(HOST_ARCH)
TARGET_PLATFORM ?= $(HOST_PLATFORM)
TARGET_ARCH ?= $(patsubst linux/%,%,$(TARGET_PLATFORM))
GO_VERSION ?= 1.26.5
GO_X_TEXT_VERSION ?= 0.39.0

BUILD_OPTS = \
	--platform=$(TARGET_PLATFORM) \
	--build-arg BUILDPLATFORM=$(BUILD_PLATFORM) \
	--build-arg BUILDARCH=$(BUILD_ARCH) \
	--build-arg TARGETARCH=$(TARGET_ARCH) \
	--build-arg GO_VERSION=$(GO_VERSION) \
	--build-arg GO_X_TEXT_VERSION=$(GO_X_TEXT_VERSION) \
	--build-arg UPSTREAM_REPOSITORY=$(UPSTREAM_REPOSITORY) \
	--build-arg UPSTREAM_TAG=$(UPSTREAM_TAG) \
	--build-arg UPSTREAM_VERSION=$(UPSTREAM_VERSION) \
	--build-arg UPSTREAM_COMMIT=$(UPSTREAM_COMMIT) \
	--build-arg UPSTREAM_ARCHIVE_SHA256=$(UPSTREAM_ARCHIVE_SHA256) \
	--build-arg SOURCE_DATE_EPOCH=$(UPSTREAM_SOURCE_DATE_EPOCH) \
	--build-arg IMAGE_VERSION=$(VERSION) \
	--build-arg SOURCE_REVISION=$(SOURCE_REVISION) \
	--provenance=false \
	--sbom=false

.PHONY: validate
validate:
	bash scripts/validate

.PHONY: image-build
image-build: validate
	docker buildx build \
		$(BUILD_OPTS) \
		--pull \
		--load \
		--tag "$(IMAGE)" \
		.

.PHONY: image-smoke
image-smoke:
	docker run --rm --network none "$(IMAGE)" --version
	docker run --rm --network none --entrypoint /usr/local/bin/etcdctl "$(IMAGE)" version
	docker run --rm --network none --entrypoint /usr/local/bin/etcdutl "$(IMAGE)" version

.PHONY: data-lifecycle
data-lifecycle:
	ETCD_IMAGE="$(IMAGE)" bash scripts/test-data-lifecycle.sh

.PHONY: image-scan
image-scan:
	trivy image --severity "$(SEVERITIES)" --no-progress "$(IMAGE)"

.PHONY: log
log:
	@echo "VERSION=$(VERSION)"
	@echo "IMAGE=$(IMAGE)"
	@echo "UPSTREAM_REPOSITORY=$(UPSTREAM_REPOSITORY)"
	@echo "UPSTREAM_TAG=$(UPSTREAM_TAG)"
	@echo "UPSTREAM_COMMIT=$(UPSTREAM_COMMIT)"
	@echo "UPSTREAM_ARCHIVE_SHA256=$(UPSTREAM_ARCHIVE_SHA256)"
	@echo "SOURCE_DATE_EPOCH=$(UPSTREAM_SOURCE_DATE_EPOCH)"
	@echo "SOURCE_REVISION=$(SOURCE_REVISION)"
	@echo "GO_VERSION=$(GO_VERSION)"
	@echo "GO_X_TEXT_VERSION=$(GO_X_TEXT_VERSION)"
	@echo "TARGET_PLATFORM=$(TARGET_PLATFORM)"
	@echo "BUILD_PLATFORM=$(BUILD_PLATFORM)"
