# Root license integrity status

This document records evidence; it is not a legal conclusion and does not replace the repository's root `LICENSE` file.

## Preserved inherited file

The root `LICENSE` has been unchanged since the preserved upstream repository's initial commit. Its authoritative Git object has these exact properties:

- Git blob ID: `2eb95ede392fef266b15e0903a24fd193fb53c48`;
- raw Git blob byte length: `10147`;
- raw Git blob SHA-256: `0d7b27a8f3b3d5297ce21a062f93aaef2124687ba52953795871061d8b3708b2`; and
- final bytes render as `END OF TERMS AND CONDITIONSn`.

The literal final `n`, missing expected normal ending, and absent appendix make the file's integrity uncertain. Checkout line-ending conversion may change the worktree byte count, so the source gate compares the Git blob rather than a platform-specific checkout hash. The file is preserved and must not be silently repaired, replaced, or used as the sole basis for a repository-wide license claim.

## Candidate image separation

The candidate image keeps these records distinct:

- `LICENSE.repository-original` — unchanged inherited repository evidence;
- `LICENSE-STATUS.md` — this integrity notice;
- `LICENSE.etcd-upstream` — the license from official etcd source commit `5e7fd0de9a57db03ecc11794dc40403a734c07bb`;
- `ETCD-UPSTREAM-BILL-OF-MATERIALS.json` and its override — the official source's dependency-license inventory; and
- `LICENSE.golang.org-x-text` — the license from the pinned `golang.org/x/text v0.39.0` module.

The official source license SHA-256 is `43ca1b4bbf462789ba15b28373e0c536e510f49e4d05d85a7690cfee94de6f49`. The pinned `golang.org/x/text` license SHA-256 is `911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad`.

Keeping these files separate avoids presenting the official source license as an unverified repair of the inherited repository file.

## Release gate

Before redistribution, obtain authoritative provenance for the inherited root license, complete human legal review, confirm the dependency-license inventory against the exact static binaries and SBOM, and preserve all required notices. Until then, do not assert that the inherited defect is cured or that one license conclusively covers every repository contribution.
