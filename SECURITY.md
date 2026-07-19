# Security boundary

The exact Runtime candidate must contain zero Critical vulnerabilities, zero High vulnerabilities, and zero detected secrets before publication can be considered. A passing source review does not itself authorize publication or deployment.

## Runtime controls

- The final image contains only three static executables, reviewed documentation, and legal evidence in a `scratch` filesystem.
- The process runs as numeric user and group `65532:65532`.
- The image has no shell, package manager, CA bundle, or implicit privileged setup path.
- Operators must supply writable storage, mutually authenticated client and peer TLS, restricted networks, authenticated clients, backups, compaction, monitoring, and tested recovery.
- Permission or certificate failures must not be worked around by making the container privileged or disabling verification.

## Supply-chain controls

- Ubuntu is content-pinned; APT uses a dated HTTPS snapshot, an explicit CA binding, and exact direct-package versions.
- The Go toolchain archive, official source commit archive, source tag mapping, source license, `golang.org/x/text` checksum records, and dependency license are fixed and verified.
- Every binary is built twice with `CGO_ENABLED=0`, `-trimpath`, no Go build ID, and the exact source and product versions.
- The official source's intentionally insecure proxy-test private key is hash-verified for provenance, used only by source tests, and deleted before the builder evidence filesystem is flattened into a new image. The scanned builder therefore has no inherited layer containing the key. It is never copied into the Runtime image; any other detected secret fails the gate.
- The manual gate scans the source tree, Runtime image, and full builder image and produces separate Runtime and builder CycloneDX SBOMs.
- The builder retains raw and applicable scan reports. Its OpenVEX document applies only when the raw Critical/High CVE and package-PURL set exactly equals all 46 reviewed `linux-libc-dev` statements.
- OpenVEX is never applied to the Runtime candidate. Any new package, package version, CVE, secret, or Runtime finding fails the gate.

The `linux-libc-dev` determination is narrow: the builder contains userspace API headers needed for Go race tests, not the vulnerable Linux kernel implementation, and those headers are not copied into the Runtime image. It is not a general waiver for kernel findings.

## Data safety

- Automated lifecycle tests use synthetic keys, uniquely named temporary volumes, no host paths, and no published ports.
- The three-member test uses a uniquely named internal Docker network, short-lived test-only CA material, mutually authenticated client and peer TLS, and no host paths or published ports. Private keys stay outside the source and evidence trees, enter only a disposable certificate volume, and are destroyed during cleanup.
- The gate must prove that missing and untrusted client certificates are rejected, writes cannot commit without quorum, recovery does not reveal the rejected write, replacement members catch up as learners before promotion, and all three active members report the same store hash after network rejoin.
- Never mount an existing data directory into the automated test.
- Follow the official minor-version and downgrade procedures; do not start an older binary against newer data without enabling and completing the supported downgrade.
- Take and verify a current snapshot before every real upgrade stage, retain the previous executable and configuration, and define explicit stop and rollback criteria.

## Reporting

Report suspected vulnerabilities through this repository's private security advisory channel. Do not include live credentials, private cluster data, production endpoints, snapshots, or topology in a public issue.
