# philips_hue

A small, dependency-light Ruby client for the **Philips Hue CLIP API v2** (the
local, on-Bridge API). It can discover a Bridge, pair to obtain an application
key, read and control lights and rooms, and subscribe to the Bridge push event
stream.

Built on the Ruby standard library (`net/http`, `json`, `openssl`, `resolv`,
`socket`) — no heavyweight runtime dependencies. Targets Ruby 4.0+.

## How Hue works (the short version)

- All control flows through a **Hue Bridge** on your LAN. The Zigbee bulbs do
  not expose an API directly; the Bridge hosts the REST API.
- The Bridge is **HTTPS-only** and serves a **self-signed certificate** whose
  common name is the Bridge ID (a 16-hex-char string), not its IP address. TLS
  verification is therefore configurable (see [TLS](#tls)).
- Everything in v2 is addressed by **UUID**. To control a whole room you write
  to its `grouped_light`, not to the room itself.
- Brightness in v2 is a **float percentage 0–100**, not the old 0–254 `bri`.

## Installation

Add to your Gemfile:

```ruby
gem 'philips_hue'
```

Then `bundle install`. Or, working from a checkout:

```sh
bin/setup            # bundle install
bundle exec rake     # run specs + rubocop
```

## Configuration

The client reads from environment variables, with constructor overrides:

| Variable         | Meaning                                              | Default |
|------------------|------------------------------------------------------|---------|
| `HUE_BRIDGE_IP`  | Bridge LAN IP address                                | —       |
| `HUE_APP_KEY`    | Application key (the `hue-application-key`)           | —       |
| `HUE_VERIFY_TLS` | `true`/`false`, or a path to a CA bundle for strict  | `false` |
| `HUE_CA_BUNDLE`  | Explicit CA bundle path for strict verification      | —       |

```ruby
hue = PhilipsHue::Client.from_env
# or
hue = PhilipsHue.new(bridge_ip: '192.168.1.42', app_key: 'your-app-key')
```

## Pairing flow

Key creation uses the Bridge's link button. Run the helper once:

```sh
ruby examples/pair.rb            # discovers a Bridge automatically
ruby examples/pair.rb 192.168.1.42   # or target a known IP
```

Press the physical link button on the Bridge when prompted. It polls for ~30s,
swallowing the "link button not pressed" error, and prints the application key
once the button is pressed. Export the values it gives you:

```sh
export HUE_BRIDGE_IP=192.168.1.42
export HUE_APP_KEY=the-printed-key
```

Programmatically:

```ruby
bridge = PhilipsHue.discover_bridges.first
key    = PhilipsHue.create_app_key(bridge.internal_ip_address, device_type: 'myapp#host')
key.username   # => the application key
key.clientkey  # => Entertainment client key (stored, otherwise unused here)
```

## Usage

```ruby
hue = PhilipsHue::Client.from_env

# Read lights
hue.get_lights.each do |light|
  puts "#{light.name}: #{light.on? ? "on @ #{light.brightness}%" : 'off'}"
end

# Control a light (brightness is clamped to 0-100)
light = hue.get_lights.first
hue.set_light(light.id, on: true, brightness: 75)
hue.set_light(light.id, on: false)

# Control a whole room/zone via its grouped_light
hue.set_group(grouped_light_id, on: true, brightness: 40)

# Colour writes are capability-gated. On a white-only bulb these no-op with a
# warning rather than raising:
hue.set_light(light.id, color_temp_mirek: 366)     # warm white
hue.set_light(light.id, xy: [0.4573, 0.41])        # colour bulbs only
```

### Event stream

Subscribe instead of polling. The block receives `PhilipsHue::HueEvent`s as the
Bridge pushes them, and the connection auto-reconnects with backoff if dropped:

```ruby
hue.events do |event|
  next unless event.update?

  event.data.each do |resource|
    puts "#{resource['type']} #{resource['id']} changed"
  end
end
```

```sh
ruby examples/demo.rb   # lists lights, toggles one, then streams events
```

## TLS

The Bridge's certificate is signed by the Signify/Philips root CA (not a public
CA) and its CN is the Bridge ID, not the IP.

- **Local/dev (default):** `verify_tls: false` disables verification and emits a
  one-time warning. Fine on a trusted LAN.
- **Strict:** pass a CA bundle path (the Signify root CA) via `verify_tls:` or
  `HUE_CA_BUNDLE`. Supply the Bridge ID via `bridge_id:` so the client connects
  to the IP while presenting the Bridge ID as the TLS hostname, letting the
  self-signed certificate's common name validate.

```ruby
hue = PhilipsHue.new(
  bridge_ip: '192.168.1.42',
  app_key: 'your-app-key',
  verify_tls: '/path/to/signify-root.pem',
  bridge_id: '001788fffe1234ab'
)
```

## Rate limits

The Bridge silently drops commands above roughly **10/second** to individual
lights and **1/second** to groups. The client throttles writes internally
(token bucket) to stay under those ceilings, so you can fire commands freely.

Never poll `GET` in a loop to track state — use the [event stream](#event-stream).

## Errors

All errors descend from `PhilipsHue::Error`:

- `PhilipsHue::HueError` — the Bridge reported a problem in the response
  `errors` array (carries `#status`, `#error_type`, `#description`). Note these
  arrive even on HTTP 200, so the client always inspects them.
- `PhilipsHue::ConnectionError` — transport failure (refused, TLS, timeout).
- `PhilipsHue::ParseError` — unparseable response body.
- `PhilipsHue::DiscoveryError` — discovery failed on every strategy.

## Out of scope

Entertainment / streaming API (DTLS), scene/automation authoring, the remote
cloud OAuth2 API, and colour science beyond passing through mirek / xy values.

## Development

```sh
bin/setup            # install dependencies
bundle exec rspec    # run the unit tests
bundle exec rubocop  # lint
bundle exec rake     # both
bin/console          # IRB with the gem loaded
```

The test suite is unit-level and uses WebMock to stub the Bridge; it does not
require real hardware. The `examples/` scripts exercise a live Bridge.

## License

ISC
