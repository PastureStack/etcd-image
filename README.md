# PastureStack etcd image

PastureStack is an independent community effort to preserve, audit, and modernize the Rancher 1.6 ecosystem. It is not affiliated with or endorsed by Rancher Labs or SUSE.

**Repository origin:** [`rancher/image-build-etcd`](https://github.com/rancher/image-build-etcd). This GitHub fork retains the inherited Git history, authorship, dates, tags, and legal notices. PastureStack maintenance is consolidated into one commit after the preserved upstream boundary.

This repository builds the PastureStack `3.7.2` compatibility-migration candidate from the verified official etcd `v3.7.1` source commit. The package version and every executable report `3.7.2`; the upstream tag and commit remain separate provenance fields. New PastureStack versions must use plain numeric semantic versions. Git and image tags may add only the standard `v` prefix.

The candidate is not published or deployed by this repository review. It remains blocked from redistribution until the inherited root-license integrity issue receives human legal review; see [LICENSE-STATUS.md](LICENSE-STATUS.md).

## Pinned inputs

| Input | Pinned value |
| --- | --- |
| PastureStack candidate | `3.7.2` |
| Official source | `etcd-io/etcd` |
| Official source tag | `v3.7.1` |
| Source commit | `5e7fd0de9a57db03ecc11794dc40403a734c07bb` |
| Source archive SHA-256 | `a9254be36198b8240fe1a5ea8018e67d9fdc148146888e7dec60c019ddc8870c` |
| Source date epoch | `1784835042` |
| Go toolchain | `1.26.5` |
| `golang.org/x/text` | `0.39.0` |
| Builder base | Ubuntu 26.04, content-pinned |
| APT snapshot | `20260808T000000Z` with exact direct-package versions |
| Target architectures | `linux/amd64`, `linux/arm64` |

The source tag maps to a signed annotated tag object and a verified signed commit. The build consumes the immutable commit archive and verifies its SHA-256 before extraction. It also verifies the Go archive, Go checksum-database records, dependency license hash, source version, and every direct APT package version.

The narrowly scoped `golang.org/x/text` update removes the vulnerable `v0.37.0` selected by the official source without changing the etcd storage format or protocol implementation. The resulting binaries are static, built twice, and compared byte for byte.

## Build

```sh
make validate
make image-build
make image-smoke
```

The default local image is `pasturestack/etcd-image:v3.7.2`. These commands load a local image only; they do not push an image, create a tag or Release, update a Catalog, or deploy a service.

## Review gates

The manual GitHub gate performs all of the following without publishing:

- formatting, `go vet`, selected storage/server/client tests under the race detector, and static AMD64/ARM64 builds;
- two independent candidate builds with byte-for-byte executable comparison;
- isolated `3.6.14 → 3.7.2 → 3.6.14` data lifecycle with the supported downgrade procedure;
- snapshot creation and restore with deterministic key/value verification;
- a disposable three-member `3.7.2` cluster with mutually authenticated client and peer TLS;
- rejection of missing and untrusted client certificates, one-member failure tolerance, loss-of-quorum write rejection, quorum recovery, learner-first member replacement, network isolation, rejoin, and cross-member hash agreement;
- source, Runtime, and builder secret and vulnerability scans;
- exact verification and post-test removal of the official source's intentionally insecure proxy-test key, followed by a flattened builder evidence image with no recoverable key layer;
- Runtime and builder CycloneDX SBOM generation; and
- exact CVE/PURL matching before the build-only OpenVEX document can affect applicable findings.

The lifecycle and quorum tests use uniquely named disposable volumes and networks, synthetic data, no published ports, and no access to existing data directories. The quorum test creates a short-lived test CA and certificates outside the source tree, copies only the required certificates and keys into a disposable volume, records public certificate fingerprints, and destroys every private key during cleanup. These gates cannot replace testing against a read-only copy of the intended cluster's real data shape and topology.

## Runtime shape

- Entrypoint: `/usr/local/bin/etcd`
- Client utility: `/usr/local/bin/etcdctl`
- Snapshot and data utility: `/usr/local/bin/etcdutl`
- Working directory: `/var/lib/etcd`
- Runtime identity: numeric user and group `65532:65532`
- Base filesystem: `scratch`
- Shell, package manager, and CA bundle: absent

Repository-origin evidence, the official source license, the official source license inventory, the reviewed dependency license, and exact source coordinates are installed under `/usr/share/licenses/pasturestack-etcd-image/` and `/usr/share/doc/pasturestack-etcd-image/`. Their presence does not cure the inherited root-license defect or replace human legal review.

## Documentation

- [ORIGIN.md](ORIGIN.md) — repository and current source provenance
- [COMPATIBILITY.md](COMPATIBILITY.md) — tested and untested boundaries
- [SECURITY.md](SECURITY.md) — security and supply-chain controls
- [LICENSE-STATUS.md](LICENSE-STATUS.md) — inherited license-integrity evidence
