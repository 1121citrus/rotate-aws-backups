# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0](https://github.com/1121citrus/rotate-aws-backups/compare/v1.1.4...v1.2.0) (2026-04-25)


### Features

* **rotate-aws-backups:** add --aws-credentials FILE / AWS_SHARED_CREDENTIALS_FILE support ([dc1e627](https://github.com/1121citrus/rotate-aws-backups/commit/dc1e627d3ceaf2c28aa2ff3137436b6e7b099d16))


### Bug Fixes

* **dependabot:** block Python Docker minor/major version bumps ([447da8d](https://github.com/1121citrus/rotate-aws-backups/commit/447da8d05c88c14b6647bb2bba8dfa5819cde040))
* **Dockerfile:** build supercronic from source to patch Go CVEs ([8d34ef9](https://github.com/1121citrus/rotate-aws-backups/commit/8d34ef988557eba0aea721a5d4803a984767149d))
* **dockerfile:** remove crontabs symlink before install -d ([1dba9e2](https://github.com/1121citrus/rotate-aws-backups/commit/1dba9e2064714559e8dbb1cc815f384c68f4e038))
* include build validation in CI test suite ([04ea613](https://github.com/1121citrus/rotate-aws-backups/commit/04ea61302c0b6b2e9d4c9ca7379f1eaee7769fc8))

## [Unreleased]

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

[Unreleased]: https://github.com/1121citrus/rotate-aws-backups/compare/v1.1.4...HEAD
[1.1.4]: https://github.com/1121citrus/rotate-aws-backups/releases/tag/v1.1.4
