# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## 0.1.0 — 2026-06-22

Initial public release.

### Added

- Six-tab LuCI UI for the NetBird client: **Authentication, Versions, Settings, Status, Network, Logs**.
- **Authentication** — setup-key login, connect / reconnect / disconnect / deregister, self-hosted management URL.
- **Versions** — switch the running binary between the official GitHub release (SHA-256 + ELF-arch verified, with auto-restore on failure), the system package feed, or a custom URL (multi-version, optional checksum).
- **Settings** — full `netbird up` configuration: WireGuard port & interface name, hostname, pre-shared key, firewall, DNS, routes, SSH (0.72.x+), IPv6, Rosenpass (post-quantum), log level. Capability-gated to the installed binary.
- **Status** — peer list (IP / FQDN / latency / last handshake / routed networks), daemon and kernel versions.
- **Network** — one-click firewall zone bound to the NetBird device (no OpenWrt network interface → zero data-plane disruption); opt-in, per-direction LAN ↔ mesh forwarding with instant-effect cancel; explicit removal.
- **Logs** — NetBird `client.log` viewer with search, severity-threshold and time-window filters, and paging.
- English + Simplified Chinese UI.
- Packaging for OpenWrt / ImmortalWrt 24.10 (opkg / ipk) and 25+ (apk); architecture-independent (`PKGARCH:=all`).
