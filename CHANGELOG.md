# Changelog

Notable changes to the Canton Data Standard packages, newest first. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the interface
packages share one version line while the standard is pre-release.

## [Unreleased]

### Added

- Producer-signed `AuditRecord` templates, one per verifier, created by every successful verify choice; they live in four template-only audit packages and share the `VerificationAudit` evidence type added to `utils-v1`.
- The `DataPointVerifier` and `PaidDataPointVerifier` interfaces, signature-based delivery for the generic data point in free and paid form, with the recursive `v1-datapoint-tlv` canonical encoding, reference producer and consumer examples, and golden-vector and settlement tests.
