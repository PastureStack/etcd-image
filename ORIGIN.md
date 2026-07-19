# Origin and attribution

`PastureStack/etcd-image` is a history-preserving GitHub fork derived from the former `rancher/image-build-etcd` repository. Historical commits, tags, automation paths, and image names remain source evidence and are not current PastureStack branding.

The current candidate compiles the official `etcd-io/etcd` source:

- tag: `v3.7.1`;
- annotated tag object: `ccd265ad64d16343b616416860e3ebe7ddd1ab83`;
- commit: `5e7fd0de9a57db03ecc11794dc40403a734c07bb`;
- commit timestamp: `2026-07-23T19:30:42Z`;
- commit verification: valid signature reported by the GitHub commit record; and
- commit-archive SHA-256: `a9254be36198b8240fe1a5ea8018e67d9fdc148146888e7dec60c019ddc8870c`.

The build consumes the commit archive rather than a moving branch. The PastureStack candidate version is `3.7.2`; `3.7.1` remains the upstream source version. Executable and OCI metadata preserve both values without a product-name or maintenance-count suffix.

PastureStack is an independent community effort to preserve, audit, and modernize the Rancher 1.6 ecosystem. It is not affiliated with or endorsed by Rancher Labs or SUSE.

Rancher, SUSE, k3s, Kubernetes, CNCF, and etcd names are used only where required for source attribution, retained history, or compatibility scope. They remain the property of their respective owners. This repository and its images must not be presented as official releases of those projects.

See [LICENSE-STATUS.md](LICENSE-STATUS.md) for the unresolved inherited root-license defect. Nothing in this document replaces or repairs a legal file.
