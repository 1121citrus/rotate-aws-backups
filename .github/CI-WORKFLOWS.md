# GitHub CI Workflows

Automated linting, building, testing, security scanning, and Docker image publication for rotate-aws-backups.

## Workflow Overview

| Stage          | Trigger                              | Purpose                                        |
| -------------- | ------------------------------------ | ---------------------------------------------- |
| **Lint**       | All pushes, PRs, tags                | Validate Dockerfile and shell scripts          |
| **Build**      | After lint                           | Build image as artifact (for smoke + scan)     |
| **Test**       | After lint (parallel with build)     | Run bats tests directly on the runner          |
| **Smoke**      | After build (parallel with scan)     | Image-level sanity checks against built image  |
| **Scan**       | After build (parallel with smoke)    | Trivy image scan — blocks push on fixable CVEs |
| **Push**       | Version tags and staging branch only | Multi-platform build and push to Docker Hub    |
| **Dependabot**     | Weekly (Monday 06:00 UTC)            | Keep GitHub Actions versions current           |
| **Release Please** | Push to main/master                  | Open release PR; create tag and GitHub Release |

## CI Workflow (`ci.yml`)

Single unified workflow for all CI/CD stages.

### Global configuration

- **Image name:** `1121citrus/rotate-aws-backups`
- **Node.js actions runtime:** v24 (via `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24`)

### Trigger Events

- **Push:** `main`, `master`, `staging` branches and `v*` version tags
- **Pull requests:** To `main` or `master` branches

### Concurrency

- **Group:** `<workflow-name>-<ref>` — one concurrent run per workflow + branch/tag
- **Branches and PRs:** Cancel any in-progress run when a newer one starts
- **Version tags:** Never cancelled — release builds always complete

### Versioning

Tag-driven. Push a git tag to publish a release:

```bash
git tag v1.2.3
git push origin v1.2.3
# Publishes: 1121citrus/rotate-aws-backups:1.2.3 + :1.2 + :1 + :latest
```

No automation bumps the version — the tag is always a deliberate decision.

---

## Stage 1: Lint

- **Hadolint** — Dockerfile best-practice checks
- **ShellCheck** — static analysis of all shell scripts:
  - `build`, `src/include/common-functions`, `src/rotate-aws-backups`, `src/startup`, `src/healthcheck`, `src/rotate`
  - `test/staging`

---

## Stage 2: Build

Builds the Docker image for `linux/amd64` and exports as a GitHub Actions artifact
(`docker-image`). The image is consumed by the smoke and scan jobs — unit tests run directly
on the runner with mock binaries.

Artifact retention: 1 day.

**Docker layer cache:** `cache-from: type=gha` / `cache-to: type=gha,mode=max` — build
layers are saved to and restored from GitHub Actions cache, speeding up incremental
builds. The push job restores from the same cache.

---

## Stage 3: Test

Runs in parallel with the build job (both depend only on lint). Executes the test suites
inside `bats/bats:1.13.0` with the repository bind-mounted:

```bash
docker run -i --rm -v "$PWD:/code:ro" -w /code bats/bats:1.13.0 \
  test/01-dockerfile.bats test/02-functional.bats
```

- `test/01-dockerfile.bats` — validates Dockerfile structure (content checks)
- `test/02-functional.bats` — validates shell script behaviour using mock binaries in `test/bin/`

Tests do not require the Docker image to be built.

---

## Stage 3b: Image smoke test

Runs in parallel with the scan job (both depend on build). Downloads the built image artifact and runs lightweight checks to catch packaging and runtime regressions that source-mounted bats tests cannot detect.

Verifies:

- **Runtime dependencies:** `bash`, `aws` CLI, `jq`, and `rotate-backups` are available inside the image
- **Include file:** `common-functions` is installed at `/usr/local/include/`
- **Entrypoint:** `--help` and `--version` exit successfully
- **Script permissions:** `healthcheck` is executable at `/usr/local/bin/`

Each check runs via `docker run --rm` — no network access or credentials required.

---

## Stage 4: Security scan

Scans the built image **before** it is pushed to Docker Hub.

- **Tool:** Trivy `aquasecurity/trivy-action@0.35.0` (pinned)
- **Severity:** CRITICAL, HIGH
- **Blocking:** `exit-code: 1` — **blocks the build and prevents push** if fixable CVEs are found
- **Noise reduction:** `ignore-unfixed: true` — suppresses CVEs with no available vendor patch
  (unfixed CVEs are reported but do not block the build)
- **DB caching:** `~/.cache/trivy` is cached between runs with `actions/cache`; the vulnerability DB is
  only re-downloaded when the cache is cold or the DB has been updated
- **Download noise:** `TRIVY_NO_PROGRESS=true` suppresses progress bars; `TRIVY_QUIET=true` suppresses
  `INFO [vulndb]` log lines during DB download

---

## Stage 5: Push to Docker Hub

Runs only when test, smoke, and scan all pass, and only on version tags or the staging branch.

### Tagging

- **Tag `v1.2.3`** → `1121citrus/rotate-aws-backups:1.2.3` + `:1.2` + `:1` + `:latest`
- **Push to `staging`** → `1121citrus/rotate-aws-backups:staging-<sha>` + `:staging`

`:latest` is set **only** on version-tagged releases. Staging uses a short commit SHA for traceability.

### Build configuration

- **Platforms:** `linux/amd64`, `linux/arm64`
- **Attestations:** `sbom: true` + `provenance: mode=max` (SLSA L3)
- **Layer cache:** `cache-from: type=gha` / `cache-to: type=gha,mode=max`

---

## Execution Flow

```text
On push/PR
    ↓
[Lint] — hadolint + shellcheck
    ↓ (parallel)
[Build]                          [Test]
 - Docker image → artifact        - install bats + jq
    ↓ (parallel)                  - run 01-dockerfile.bats
[Smoke]        [Scan]             - run 02-functional.bats
 - bash, aws    - Trivy
 - jq, rotate     CRITICAL/HIGH
 - --help/ver
    ↓ (test + smoke + scan must pass)
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
- `build` — Build helper script (shellchecked)
- `src/rotate-aws-backups` — Main rotation script
- `src/rotate` — Rotation helper
- `src/startup` — Container startup script
- `src/healthcheck` — Container health check script
- `src/include/common-functions` — Shared shell library
- `test/01-dockerfile.bats` — Dockerfile content tests
- `test/02-functional.bats` — Shell script functional tests
- `test/03-build.bats` — Build artifact validation tests
- `test/bin/` — Mock binaries (aws, jq, rotate-backups)
- `test/staging` — Integration test script with real S3 bucket support

---

## Automated dependency updates

`dependabot.yml` configures weekly automated PRs to keep GitHub Actions current.

- **Schedule:** Every Monday at 06:00 UTC
- **Scope:** GitHub Actions (`package-ecosystem: github-actions`) — updates action pins in
  `.github/workflows/*.yml`
- **Labels:** `dependencies`, `github-actions`
- **Security benefit:** Dependabot also proposes SHA-pinned digests (recommended for SLSA /
  OpenSSF Scorecard hardening)

---

## Automated releases (release-please)

`release-please.yml` watches for [conventional commits](https://www.conventionalcommits.org/)
merged to `main`/`master` and automates the release lifecycle:

1. Opens a "release PR" that bumps `version.txt`, prepends to `CHANGELOG.md`, and proposes the next semver tag
2. When the release PR is merged, creates a GitHub Release and pushes the version tag
3. The existing CI `push` job fires on the new tag and builds and publishes the Docker image

### Conventional commit types that trigger version bumps

| Commit prefix | Bump |
|---|---|
| `fix:` | patch (1.0.x) |
| `feat:` | minor (1.x.0) |
| `feat!:` or `BREAKING CHANGE:` | major (x.0.0) |

All other prefixes (`ci:`, `docs:`, `chore:`, `refactor:`, `test:`, etc.) appear in the
changelog but do not trigger a version bump on their own.

### Configuration

- `release-please-config.json` — release type (`simple`) and package root
- `.release-please-manifest.json` — current version (updated by release-please on each release)
- `version.txt` — plain-text version file (updated by release-please; can be referenced in Dockerfile)
- `CHANGELOG.md` — generated/updated by release-please
