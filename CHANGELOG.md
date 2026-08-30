## 0.4.0

- Support device-only certificates when no customer or Core ID exists.
- Require at least one expected customer/Core or device identity.
- Add hash-based `syncByDevice` without exposing the raw device secret in URLs.

## 0.3.0

- Add offline-first AtomCyou synchronization for active licenses.
- Verify every downloaded certificate before updating secure local storage.
- Add independent signed customer and device identity validation.
- Add secure random installation identities and SHA-256 device binding.

## 0.2.0

- Add explicit separate and replace licensing models.
- Replace a different plan immediately in replace mode while preserving normal same-plan extension behavior.

## 0.1.1

- Update direct dependencies to their current stable releases.
- Improve public API documentation coverage.

## 0.1.0

- Initial offline Ed25519 license verification API.
- Product, time, optional Core ID, storage, plan metadata, and feature entitlement support.
- Trusted-key rotation using `key_id` and `<key_id>.pub` assets.
