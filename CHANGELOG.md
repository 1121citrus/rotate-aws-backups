# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/1121citrus/rotate-aws-backups/compare/v1.1.9...HEAD
[1.1.9]: https://github.com/1121citrus/rotate-aws-backups/releases/tag/v1.1.9
[1.1.7]: https://github.com/1121citrus/rotate-aws-backups/releases/tag/v1.1.7
[1.1.4]: https://github.com/1121citrus/rotate-aws-backups/releases/tag/v1.1.4
