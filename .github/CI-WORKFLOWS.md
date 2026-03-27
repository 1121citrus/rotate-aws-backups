# GitHub CI workflows

Automated linting, building, testing, security scanning, and Docker image publication
for rotate-aws-backups.

## Workflow overview

| Stage | Trigger | Purpose |
| ----- | ------- | ------- |
| **Lint** | All pushes, PRs to main/master, tags | Validate Dockerfile and shell scripts |
| **Build** | After lint | Build image and share as artifact |
| **Test** | After lint (parallel with build) | Run bats suite with mock binaries |
| **Smoke** | After build (parallel with test/scan) | Quick sanity checks against the built image |
| **Scan** | After build (parallel with test/smoke) | Trivy image scan — blocks push on fixable CVEs |
| **Push** | Version tags and staging branch only | Multi-platform build and push to Docker Hub |
| **Dependabot** | Weekly (Monday 06:00 UTC) | Keep GitHub Actions versions current |
| **Release Please** | Push to main/master | Open release PR; create tag and GitHub Release |

## CI workflow (`ci.yml`)

Lint, Build, Scan, and Push delegate to shared reusable workflows in
[1121citrus/shared-github-workflows](https://github.com/1121citrus/shared-github-workflows).
The Test and Smoke jobs are defined inline because they are specific to this repo.

### Global configuration

- **Image name:** `1121citrus/rotate-aws-backups`

### Trigger events

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

---

## Stage 1: Lint

Shared workflow: `lint.yml` — runs Hadolint, ShellCheck, and markdownlint-cli.

---

## Stage 2: Build

Shared workflow: `build.yml` — builds image once and exports it as the
`docker-image` artifact for smoke and scan jobs. Re-tagged as `:latest`.
Artifact retention: 1 day.

---

## Stage 3: Test

Inline job. Runs in parallel with Build (depends only on Lint). The bats suite
mounts the project source read-only into `bats/bats:1.13.0`. Mock binaries in
`test/bin/` stub `aws`, `jq`, and `rotate-backups` — no host packages required:

```bash
docker run -i --rm -v "$PWD:/code:ro" -w /code bats/bats:1.13.0 \
  test/01-dockerfile.bats test/02-functional.bats test/03-build.bats
```

---

## Stage 3b: Smoke

Inline job. Downloads the built artifact and verifies the image packaging:

- `bash`, `aws`, `jq`, `rotate-backups` — available and runnable
- `/usr/local/include/common-functions` — present
- `--help`, `--version` flags — exit 0
- `healthcheck` — executable

---

## Stage 4: Security scan

Shared workflow: `scan.yml` — Trivy CRITICAL/HIGH scan of the built image.
Fails and blocks push on any fixable CVE.

---

## Stage 5: Push to Docker Hub

Shared workflow: `push.yml` — runs only when test, smoke, and scan all pass,
and only on version tags or the staging branch.

### Tagging

| Trigger | Docker Hub tags |
| ------- | --------------- |
| Tag `v1.2.3` | `1121citrus/rotate-aws-backups:1.2.3` + `:1.2` + `:1` + `:latest` |
| Push to `staging` | `1121citrus/rotate-aws-backups:staging-<sha>` + `:staging` |

### Build configuration

- **Platforms:** `linux/amd64`, `linux/arm64`
- **Attestations:** `sbom: true` + `provenance: mode=max` (SLSA L3)

---

## Execution flow

```text
On push/PR
    ↓
[Lint] — shared: hadolint + shellcheck + markdownlint
    ↓ (parallel)
[Build] — shared               [Test] — bats + mock binaries
    ↓ (parallel)
[Smoke]   [Scan] — shared Trivy
 - :latest checks

[Push] (tags and staging only, after Test + Smoke + Scan pass)
 - shared: QEMU + Buildx multi-arch
 - push amd64 + arm64
 - SBOM + provenance
```

---

## Configuration reference

### Required secrets

- `DOCKERHUB_USERNAME` — Docker Hub account
- `DOCKERHUB_TOKEN` — Docker Hub access token

### Key files

- `Dockerfile` — container build definition
- `src/rotate-backups`, `src/entrypoint`, `src/healthcheck` — application scripts
- `src/common-functions` — shared shell library
- `test/` — bats test suite
- `test/bin/` — mock binaries (aws, jq, rotate-backups)

## Automated dependency updates

`dependabot.yml` configures weekly automated PRs to keep GitHub Actions current.

---

## Automated releases (release-please)

`release-please.yml` delegates to the shared `release-please.yml` workflow.

### Configuration

- `release-please-config.json` — release type and package root
- `.release-please-manifest.json` — current version
- `version.txt` — plain-text version file
- `CHANGELOG.md` — generated/updated by release-please
