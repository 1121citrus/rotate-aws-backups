# Contributing

## Prerequisites

- Docker with buildx support
- Bash 4.0+
- [Bats](https://github.com/bats-core/bats-core) (tests run in the official
  `bats/bats:latest` container — no local installation required)
- AWS credentials and an S3 bucket for the full staging suite (optional)

## Development Workflow

### Building

The `build` script runs all stages: lint → build → test → scan → advise → push.

```bash
./build              # Local build and test
./build --push       # Push to Docker Hub after successful scan
./build --help       # See all options
```

Individual stages can be skipped:

```bash
./build --no-lint    # Skip hadolint and shellcheck
./build --no-scan    # Skip Trivy (and advisory scans by default)
./build --no-test    # Skip the bats test suite
```

### Testing

The automated suite runs through the build script or directly:

```bash
./build --no-lint --no-scan   # Lint + build + test only

# Or run bats directly against the image:
IMAGE=1121citrus/rotate-aws-backups:dev-abc123 test/run-all
```

See `test/README.md` for the full test layout and `test/staging` for
pre-release end-to-end validation.

### Code Style

All shell scripts must pass:

```bash
shellcheck src/**/*.sh
hadolint Dockerfile
```

These checks run automatically in Stage 1 of `./build`.

### Advisory Scans

Non-gating Grype, Docker Scout, and Dive scans are available:

```bash
./build --advise              # Default: grype + scout
./build --advise all          # All three: grype, scout, dive
./build --advise grype,dive   # Specific combination
```

### Submitting Changes

1. Branch from `main`.
2. Make your changes.
3. Run `./build` to lint, test, and scan.
4. Submit a pull request targeting `main`.

## Release Process

Releases are tag-driven:

```bash
git tag v1.2.3
git push origin v1.2.3
```

Pushing a version tag triggers the GitHub Actions workflow to build a
multi-platform image (`linux/amd64`, `linux/arm64`) and push it to Docker Hub
tagged as both `1.2.3` and `latest`, with SLSA provenance and SBOM attestations.

See `.github/CI-WORKFLOWS.md` for the full CI pipeline description.
