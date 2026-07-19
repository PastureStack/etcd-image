# Compatibility boundary

This repository builds an etcd image intended for a reviewed compatibility-migration path. It does not claim drop-in replacement safety for an untested cluster.

## Candidate contract

- PastureStack package and executable version: `3.7.2`.
- Official source version: `3.7.1` at the immutable commit recorded in [ORIGIN.md](ORIGIN.md).
- Static Linux binaries: `etcd`, `etcdctl`, and `etcdutl` for AMD64 and ARM64.
- Runtime: `scratch`, numeric user and group `65532:65532`, writable data directory supplied by the operator.
- API and persisted-data family: etcd v3; the candidate does not restore removed v2 API support.

## Manual gate scope

The manual security gate is required to establish the following for the exact final commit:

- current Go formatting, vet, race, pointer, client, server, WAL, backend, MVCC, and schema checks selected by the workflow;
- AMD64 Runtime smoke tests and ARM64 static executable inspection;
- independently rebuilt executable bytes are identical;
- 100 synthetic keys survive the `3.6.14 → 3.7.2` upgrade;
- a key written after upgrade survives the supported downgrade procedure to `3.6` and restart with the `3.6.14` baseline;
- a pre-upgrade snapshot restores with `3.7.2`, retains exactly the original 100 keys, and excludes the post-snapshot key; and
- a disposable three-member `3.7.2` cluster uses mutually authenticated client and peer TLS, rejects missing and untrusted client certificates, continues with one member unavailable, rejects a write after loss of quorum, recovers quorum without committing that write, replaces the unavailable member through learner catch-up and promotion, survives one-member network isolation, rejoins, and reports matching cross-member data hashes; and
- source, Runtime, builder, SBOM, license, and evidence controls pass.

The baseline build uses the previously reviewed `k3s-io/etcd` `v3.6.14-k3s1` commit only as an isolated migration fixture. Its branded upstream tag is provenance, not a PastureStack product version.

## Not established

The source and isolated image gate does not establish:

- compatibility with a live production data directory or topology;
- a safe rolling change for an existing multi-member quorum;
- production certificate issuance, certificate or CA rotation, revocation, external network policy, or long-running partition behavior;
- integration with the preserved platform server, Catalog templates, health checks, orchestration metadata, Kubernetes control plane, or Helm state;
- workload continuity, failure-domain behavior, disaster recovery, or rollback in the intended VM environment; or
- legal clearance to redistribute the inherited repository.

Before deployment, test a read-only copy of the real data shape and complete topology, every client, backup and restore, supported downgrade, certificate rotation, member replacement, loss of quorum, and full platform rollback. Do not point this repository's disposable test at an existing volume.
