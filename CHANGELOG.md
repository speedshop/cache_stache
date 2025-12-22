# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0]

### Changed

- **Breaking:** Replaced `redis_url` config option with `redis`, which accepts a Proc, String URL, or Redis-compatible object

## [0.1.1]

- Fixed Rails dependency to be >=, not ~>

## [0.1.0]

### Added

- Initial release
- Cache hit/miss rate tracking via Rails instrumentation
- Redis-backed statistics storage
- Dashboard UI for viewing cache metrics
- Keyspace breakdown view
- Configurable time windows (minute, hour, day)
- Rake tasks for cache statistics
