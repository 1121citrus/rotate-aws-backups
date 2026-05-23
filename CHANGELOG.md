# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.15] - 2026-05-23

### Changed

- Raise minimum constraints to `idna>=3.16` and `zipp>=4.1.0`
- Remove invalid `pip` labels from Dependabot configuration

## [1.1.14] - 2026-05-14

### Added

- Add advisory stages for metrics, security, and churn (`5f`, `5g`, `5h`)

### Changed

- Bump runtime/tooling minimums: `cryptography>=48.0.0`, `idna>=3.15`,
  `urllib3>=2.7.0`, and Go `1.26.3`
- Regenerate `build` to remove the invalid `env ... run ./test/run-all`
  wrapper
- Refresh `doc/known-vulnerabilities.md` with open and remediated findings

### Fixed

- Write the healthcheck success marker after CLI-mode rotation completes
- Use `stat -c %Y` for mtime checks instead of BSD-only `stat -f %m`

## [1.1.13] - 2026-05-04

### Added

- Add `gitleaks` CI workflow for secret scanning
- Regenerate `build` and `test/staging` scripts with gitleaks advisement support and dive output filter

## [1.1.12] - 2026-05-01

### Changed

- Bump base image from `python:3.13-alpine3.23` to `python:3.14-alpine3.22`
- Fix SC2140 (unescaped quotes in echo) in `test/staging`

## [1.1.11] - 2026-04-27

### Fixed

- Add `pipes` compatibility shim for Python 3.13: the `executor` package
  (transitive dependency of `rotate-backups`) imports the `pipes` module
  which was removed in Python 3.13. Installs a one-line stub in
  site-packages that re-exports `shlex.quote` as `pipes.quote`
- Correct AWS CLI entrypoint path in staging `_aws()` helper

### Changed

- Bump pip minimum constraints: `cryptography>=47.0.0`, `idna>=3.13`,
  `setuptools>=82.0.1`, `zipp>=3.23.1`
- Switch Dependabot schedule from weekly to daily; update Docker ecosystem
  comment to reflect current `python:3.13-alpine3.23` base

### Added

- Staging test: add `--advise` and `--cache` options

## [1.1.10] - 2026-04-26

### Changed

- Security refresh for the runtime image:
  Dockerfile now uses `python:3.13-alpine3.23`, replaces Alpine `jq`
  with `gojq`, and installs AWS CLI via `pip` to clear High and Critical
  CVEs from the local build pipeline

## [1.1.9] - 2026-04-25

### Changed

- Maintenance release

## [1.1.7] - 2026-04-25

### Fixed

- Dockerfile: remove `/var/spool/cron/crontabs` Alpine symlink before
  `install -d` so the directory is owned by the service user, not root

### Added

- `test/staging`: credential-free `test_staging_cron_startup` test that
  starts the scheduler in service mode and verifies the crontab file is
  written — catches crontabs permission regressions that CLI-mode tests miss

## [1.1.4] - 2025-03-25

### Added

- Initial release

[Unreleased]: https://github.com/1121citrus/rotate-aws-backups/compare/v1.1.15...HEAD
[1.1.15]: https://github.com/1121citrus/rotate-aws-backups/compare/d365a23...8bdce26
[1.1.14]: https://github.com/1121citrus/rotate-aws-backups/compare/v1.1.13...v1.1.14
[1.1.13]: https://github.com/1121citrus/rotate-aws-backups/compare/v1.1.12...v1.1.13
[1.1.12]: https://github.com/1121citrus/rotate-aws-backups/compare/v1.1.11...v1.1.12
[1.1.11]: https://github.com/1121citrus/rotate-aws-backups/compare/v1.1.10...v1.1.11
[1.1.10]: https://github.com/1121citrus/rotate-aws-backups/releases/tag/v1.1.10
[1.1.9]: https://github.com/1121citrus/rotate-aws-backups/releases/tag/v1.1.9
[1.1.7]: https://github.com/1121citrus/rotate-aws-backups/releases/tag/v1.1.7
[1.1.4]: https://github.com/1121citrus/rotate-aws-backups/releases/tag/v1.1.4
