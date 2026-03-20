# GitHub CI Workflows

Automated linting, building, testing, security scanning, and Docker image publication for rotate-aws-backups.

## Workflow Overview

| Stage     | Trigger                              | Purpose                                        |
| --------- | ------------------------------------ | ---------------------------------------------- |
| **Lint**  | All pushes, PRs, tags                | Validate Dockerfile and shell scripts          |
| **Build** | After lint                           | Build image as artifact (for scan)             |
| **Test**  | After lint (parallel with build)     | Run bats tests directly on the runner          |
| **Scan**  | After build                          | Trivy image scan — blocks push on fixable CVEs |
| **Push**  | Version tags and staging branch only | Multi-platform build and push to Docker Hub    |

## CI Workflow (`ci.yml`)

Single unified workflow for all CI/CD stages.

### Trigger Events

- **Push:** `main`, `staging` branches and `v*` version tags
- **Pull requests:** To `main` or `master` branches

### Versioning

Tag-driven. Push a git tag to publish a release:

```bash
git tag v1.2.3
git push origin v1.2.3
# Publishes: 1121citrus/rotate-aws-backups:1.2.3 + :latest
```

No automation bumps the version — the tag is always a deliberate decision.

---

## Stage 1: Lint

- **Hadolint** — Dockerfile best-practice checks
- **ShellCheck** — static analysis of `src/` shell scripts:
  - `src/rotate-aws-backups`, `src/startup`, `src/healthcheck`, `src/rotate`
  - `src/include/common-functions`

---

## Stage 2: Build

Builds the Docker image for `linux/amd64` and exports as a GitHub Actions artifact (`docker-image`). The image is used only by the scan job — tests run directly on the runner.

Artifact retention: 1 day.

---

## Stage 3: Test

Runs in parallel with the build job (both depend only on lint). Installs `bats` and `jq` directly on the runner and executes the test suites:

- `test/01-dockerfile.bats` — validates Dockerfile structure (content checks)
- `test/02-functional.bats` — validates shell script behaviour using mock binaries in `test/bin/`

Tests do not require the Docker image to be built.

---

## Stage 4: Security scan

Scans the built image **before** it is pushed to Docker Hub.

- **Tool:** Trivy `aquasecurity/trivy-action@0.35.0` (pinned)
- **Severity:** CRITICAL, HIGH
- **Blocking:** `exit-code: 1` — fails and blocks push if fixable CVEs found
- **Noise reduction:** `ignore-unfixed: true` — suppresses CVEs with no available patch

---

## Stage 5: Push to Docker Hub

Runs only when test and scan both pass, and only on version tags or the staging branch.

### Tagging

- **Tag `v1.2.3`** → `1121citrus/rotate-aws-backups:1.2.3` + `:latest`
- **Push to `staging`** → `1121citrus/rotate-aws-backups:staging-<timestamp>` + `:staging`

`:latest` is set **only** on version-tagged releases. Staging gets a datetime timestamp for traceability.

### Build configuration

- **Platforms:** `linux/amd64`, `linux/arm64`
- **Attestations:** `sbom: true` + `provenance: mode=max` (SLSA L3)

---

## Execution Flow

```
On push/PR
    ↓
[Lint] — hadolint + shellcheck
    ↓ (parallel)
[Build]                          [Test]
 - Docker image → artifact        - install bats + jq
 - for scan only                  - run 01-dockerfile.bats
    ↓                             - run 02-functional.bats
[Scan] — Trivy CRITICAL/HIGH
    ↓ (both test + scan must pass)
[Push] (tags and staging only)
 - QEMU + Buildx multi-arch
 - push amd64 + arm64
 - SBOM + provenance
```

---

## Configuration Reference

### Required Secrets

- `DOCKERHUB_USERNAME` — Docker Hub account
- `DOCKERHUB_TOKEN` — Docker Hub access token

### Key Files

- `Dockerfile` — Container build definition
- `src/rotate-aws-backups` — Main rotation script
- `src/rotate` — Rotation helper
- `src/include/common-functions` — Shared shell library
- `test/01-dockerfile.bats` — Dockerfile content tests
- `test/02-functional.bats` — Shell script functional tests
- `test/bin/` — Mock binaries (aws, jq, rotate-backups)
