# Security Policy

We take the security of Flux seriously. Thank you for helping keep Flux and its
users safe.

## Supported versions

Security fixes are provided for the **latest released version** of the Flux
Community edition on the `main` branch. Older versions are not maintained;
please upgrade before reporting an issue against an outdated release.

## Reporting a vulnerability

**Please do not open a public GitHub issue, pull request, or discussion for a
security vulnerability.** Public disclosure before a fix is available puts users
at risk.

Instead, report privately through either:

- **GitHub Security Advisories** — use the **"Report a vulnerability"** button
  under this repository's **Security** tab
  ([Security → Advisories](https://github.com/Mossa-Labs/flux/security/advisories/new)).
  This is the preferred channel.
- **Email** — <security@mossalabs.com> for cases where you cannot use GitHub.

Please include enough detail for us to reproduce and assess the issue:

- A description of the vulnerability and its impact
- Steps to reproduce, or a proof of concept
- Affected version / commit SHA and relevant configuration
- Your Flux, Elixir, and OTP versions

## What to expect

| Stage | Target |
|-------|--------|
| Acknowledgement of your report | within **3 business days** |
| Initial assessment & severity triage | within **7 business days** |
| Fix or mitigation plan communicated | depends on severity, kept up to date |

We will keep you informed throughout, coordinate a disclosure timeline with you,
and credit you in the advisory once a fix ships (unless you prefer to remain
anonymous).

## Release integrity

Container images published from this repository carry **SLSA build provenance**
and a **software bill of materials**. Both travel inside the image index, so
there is nothing extra to download:

```bash
docker buildx imagetools inspect ghcr.io/mossa-labs/flux/community:<version> \
  --format '{{ json .Provenance }}'
docker buildx imagetools inspect ghcr.io/mossa-labs/flux/community:<version> \
  --format '{{ json .SBOM }}'
```

The provenance records which workflow, repository and commit produced the image,
and what went into the build. Applies to **v0.2.3 and later**.

To pin a deployment to exactly the artifact you inspected, use the digest rather
than the tag — a tag is a moving pointer:

```bash
docker pull ghcr.io/mossa-labs/flux/community@sha256:<digest>
```

Each release run prints its digest in the workflow summary.

**The SBOM describes the operating-system layer, not the Elixir application.**
The scanner that produces it enumerates distribution packages and detected
binaries; it does not read the OTP applications that make up the release, so
Hex dependencies are absent. Treat it as a bill of materials for the base image.
Depending on it for Elixir dependency vulnerability matching would give you
false confidence.

### On signatures

Releases **after v0.2.4** carry a signed **GitHub artifact attestation**. It is
signed keylessly through Sigstore's public-good instance, against the identity of
this repository's release workflow, and recorded in the public Rekor transparency
log. There is no long-lived signing key to leak or rotate.

Verify it with the [GitHub CLI](https://cli.github.com/):

```bash
gh attestation verify oci://ghcr.io/mossa-labs/flux/community:<version> \
  --owner Mossa-Labs
```

To also pin the exact repository and workflow that must have signed it:

```bash
gh attestation verify oci://ghcr.io/mossa-labs/flux/community:<version> \
  --repo Mossa-Labs/flux \
  --signer-workflow Mossa-Labs/flux/.github/workflows/release.yml
```

Use `@sha256:<digest>` in place of `:<version>` to verify exactly what you deploy.

The attestation is issued over the multi-arch image index, which commits to every
platform image and to the provenance and SBOM inside it, so one verification
covers all of them. The attestation bundle is also stored in the registry next to
the image (`--bundle-from-oci` reads it from there).

What it proves: the index at that digest was built by this repository's release
workflow, from the commit recorded in the provenance. What it does not prove: that
the code at that commit is free of defects, or anything about the Elixir
dependencies beyond the SBOM caveat above.

Verification contacts both the registry and the GitHub API, so it needs network
access and cannot be done offline. Releases up to and including v0.2.4 are not
signed.

If you want an assurance that does not depend on this pipeline, build from
source: everything in the image is produced from this repository, with no
external revision to resolve, so a release is reproducible from its tag.

## Scope

This policy covers the Flux **Community edition** in this repository. Pro and
Enterprise features ship in a separate, privately maintained distribution; if
your report concerns a commercial-edition feature, please still use the private
channels above and we will route it to the right maintainers.

## Safe harbor

We will not pursue or support legal action against researchers who:

- Make a good-faith effort to follow this policy,
- Avoid privacy violations, data destruction, and service degradation, and
- Give us reasonable time to remediate before public disclosure.

Thank you for practicing responsible disclosure.
