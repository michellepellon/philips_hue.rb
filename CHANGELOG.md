# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-29

### Added

- Initial release of the Philips Hue CLIP API v2 client.
- Bridge discovery via mDNS (`_hue._tcp.local`) with cloud fallback
  (`discovery.meethue.com`).
- Pairing via `PhilipsHue::Client.create_app_key`, polling the legacy
  registration endpoint until the link button is pressed.
- Reading lights (`#get_lights`, `#get_light`) as immutable `Light` value objects.
- Controlling lights (`#set_light`) and rooms/zones (`#set_group`) with
  brightness clamped to the v2 0-100 float scale.
- Capability-gated colour and colour-temperature writes (no-op with a warning on
  white-only bulbs).
- Push event stream (`#events`) with SSE framing, JSON decoding, and automatic
  reconnect with exponential backoff.
- Built-in write throttling (~10 commands/second to lights, ~1/second to groups).
- Configurable TLS: disabled-with-warning for local dev, or strict verification
  against a bundled CA with Bridge-ID hostname override.
