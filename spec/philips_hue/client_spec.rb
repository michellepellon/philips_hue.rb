# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PhilipsHue::Client do
  let(:ip) { '192.168.1.42' }
  let(:app_key) { 'super-secret-key' }
  let(:base) { "https://#{ip}" }
  let(:light_limiter) { instance_double(PhilipsHue::RateLimiter, acquire: nil) }
  let(:group_limiter) { instance_double(PhilipsHue::RateLimiter, acquire: nil) }

  subject(:client) do
    described_class.new(bridge_ip: ip, app_key: app_key, light_limiter: light_limiter, group_limiter: group_limiter)
  end

  let(:white_light_attrs) do
    {
      'id' => 'L1', 'id_v1' => '/lights/1', 'type' => 'light',
      'metadata' => { 'name' => 'Office' },
      'on' => { 'on' => true },
      'dimming' => { 'brightness' => 50.0 }
    }
  end

  let(:color_light_attrs) do
    white_light_attrs.merge(
      'color_temperature' => { 'mirek' => 250 },
      'color' => { 'xy' => { 'x' => 0.4, 'y' => 0.4 } }
    )
  end

  def light_body(*attrs)
    JSON.dump('errors' => [], 'data' => attrs)
  end

  describe '#initialize and #inspect' do
    it 'redacts the application key from inspect output' do
      expect(client.inspect).not_to include(app_key)
      expect(client.inspect).to include(ip)
    end

    it 'builds default limiters when none are injected' do
      plain = described_class.new(bridge_ip: ip, app_key: app_key)
      expect(plain).to be_a(described_class)
    end
  end

  describe '.from_env' do
    def with_env(vars)
      saved = vars.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      saved.each { |key, value| ENV[key] = value }
    end

    it 'builds a client from the environment' do
      with_env('HUE_BRIDGE_IP' => ip, 'HUE_APP_KEY' => app_key, 'HUE_VERIFY_TLS' => 'false') do
        built = described_class.from_env
        expect(built).to be_a(described_class)
        expect(built.inspect).to include(ip)
      end
    end

    it 'lets explicit overrides win over the environment' do
      with_env('HUE_BRIDGE_IP' => ip, 'HUE_APP_KEY' => app_key) do
        built = described_class.from_env(bridge_ip: '10.0.0.9')
        expect(built.inspect).to include('10.0.0.9')
        expect(built.inspect).not_to include(ip)
      end
    end

    it 'raises when required variables are missing' do
      with_env('HUE_BRIDGE_IP' => nil, 'HUE_APP_KEY' => nil) do
        expect { described_class.from_env }.to raise_error(PhilipsHue::Error, /required/)
      end
    end
  end

  describe '#get_lights' do
    it 'fetches and parses lights, sending the application key header' do
      stub = stub_request(:get, "#{base}/clip/v2/resource/light")
             .with(headers: { 'hue-application-key' => app_key })
             .to_return(status: 200, body: light_body(white_light_attrs))

      lights = client.get_lights

      expect(stub).to have_been_requested
      expect(lights.size).to eq(1)
      expect(lights.first.name).to eq('Office')
      expect(lights.first.brightness).to eq(50.0)
    end
  end

  describe '#get_light' do
    it 'returns a single light' do
      stub_request(:get, "#{base}/clip/v2/resource/light/L1")
        .to_return(status: 200, body: light_body(white_light_attrs))

      expect(client.get_light('L1').id).to eq('L1')
    end

    it 'raises HueError when no data is returned' do
      stub_request(:get, "#{base}/clip/v2/resource/light/missing")
        .to_return(status: 200, body: light_body)

      expect { client.get_light('missing') }.to raise_error(PhilipsHue::HueError)
    end
  end

  describe '#set_light' do
    it 'sends on/off and a clamped 0-100 float brightness, after acquiring a token' do
      stub = stub_request(:put, "#{base}/clip/v2/resource/light/L1")
             .with(body: { 'on' => { 'on' => true }, 'dimming' => { 'brightness' => 100.0 } })
             .to_return(status: 200, body: light_body)

      client.set_light('L1', on: true, brightness: 150)

      expect(light_limiter).to have_received(:acquire)
      expect(stub).to have_been_requested
    end

    it 'clamps a negative brightness to 0.0' do
      stub = stub_request(:put, "#{base}/clip/v2/resource/light/L1")
             .with(body: { 'dimming' => { 'brightness' => 0.0 } })
             .to_return(status: 200, body: light_body)

      client.set_light('L1', brightness: -20)

      expect(stub).to have_been_requested
    end

    it 'drops colour temperature and warns for a white-only bulb, making no request' do
      allow(client).to receive(:get_light).with('L1').and_return(PhilipsHue::Light.from_api(white_light_attrs))

      expect { client.set_light('L1', color_temp_mirek: 366) }
        .to output(/does not support color_temperature/).to_stderr

      expect(a_request(:put, "#{base}/clip/v2/resource/light/L1")).not_to have_been_made
    end

    it 'still applies on/off while dropping an unsupported colour field' do
      allow(client).to receive(:get_light).with('L1').and_return(PhilipsHue::Light.from_api(white_light_attrs))
      stub = stub_request(:put, "#{base}/clip/v2/resource/light/L1")
             .with(body: { 'on' => { 'on' => true } })
             .to_return(status: 200, body: light_body)

      expect { client.set_light('L1', on: true, color_temp_mirek: 366) }.to output.to_stderr

      expect(stub).to have_been_requested
    end

    it 'sends colour temperature for a colour-capable bulb' do
      allow(client).to receive(:get_light).with('L1').and_return(PhilipsHue::Light.from_api(color_light_attrs))
      stub = stub_request(:put, "#{base}/clip/v2/resource/light/L1")
             .with(body: { 'color_temperature' => { 'mirek' => 366 } })
             .to_return(status: 200, body: light_body)

      client.set_light('L1', color_temp_mirek: 366)

      expect(stub).to have_been_requested
    end

    it 'sends an xy colour for a colour-capable bulb' do
      allow(client).to receive(:get_light).with('L1').and_return(PhilipsHue::Light.from_api(color_light_attrs))
      stub = stub_request(:put, "#{base}/clip/v2/resource/light/L1")
             .with(body: { 'color' => { 'xy' => { 'x' => 0.5, 'y' => 0.3 } } })
             .to_return(status: 200, body: light_body)

      client.set_light('L1', xy: [0.5, 0.3])

      expect(stub).to have_been_requested
    end

    it 'is a no-op returning nil when no fields are given' do
      expect(client.set_light('L1')).to be_nil
      expect(a_request(:put, "#{base}/clip/v2/resource/light/L1")).not_to have_been_made
    end
  end

  describe '#set_group' do
    it 'PUTs to the grouped_light resource and acquires the group limiter' do
      stub = stub_request(:put, "#{base}/clip/v2/resource/grouped_light/G1")
             .with(body: { 'on' => { 'on' => false }, 'dimming' => { 'brightness' => 25.0 } })
             .to_return(status: 200, body: light_body)

      client.set_group('G1', on: false, brightness: 25)

      expect(group_limiter).to have_received(:acquire)
      expect(stub).to have_been_requested
    end
  end

  describe 'error handling' do
    it 'raises HueError carrying the description when the errors array is non-empty on HTTP 200' do
      body = JSON.dump('errors' => [{ 'description' => 'device unreachable', 'type' => 7 }], 'data' => [])
      stub_request(:get, "#{base}/clip/v2/resource/light").to_return(status: 200, body: body)

      expect { client.get_lights }.to raise_error(PhilipsHue::HueError) do |error|
        expect(error.description).to eq('device unreachable')
        expect(error.error_type).to eq(7)
      end
    end

    it 'raises HueError with the status for a non-2xx response' do
      stub_request(:get, "#{base}/clip/v2/resource/light").to_return(status: 500, body: '{}')

      expect { client.get_lights }.to raise_error(PhilipsHue::HueError) do |error|
        expect(error.status).to eq(500)
      end
    end

    it 'retries a transient transport failure with backoff and then succeeds' do
      slept = []
      retrying = described_class.new(
        bridge_ip: ip, app_key: app_key,
        light_limiter: light_limiter, group_limiter: group_limiter,
        sleeper: ->(seconds) { slept << seconds }
      )
      stub_request(:get, "#{base}/clip/v2/resource/light")
        .to_raise(Errno::ECONNREFUSED).then
        .to_return(status: 200, body: light_body(white_light_attrs))

      expect(retrying.get_lights.map(&:id)).to eq(['L1'])
      expect(slept.size).to eq(1)
    end

    it 'gives up with a ConnectionError after exhausting retries' do
      retrying = described_class.new(bridge_ip: ip, app_key: app_key, sleeper: ->(_s) {})
      stub_request(:get, "#{base}/clip/v2/resource/light").to_raise(Errno::ECONNREFUSED)

      expect { retrying.get_lights }.to raise_error(PhilipsHue::ConnectionError)
    end
  end

  describe '.create_app_key' do
    let(:registration) { "#{base}/api" }

    it 'polls past a link-button error and returns the AppKey on success' do
      stub_request(:post, registration)
        .to_return(body: JSON.dump([{ 'error' => { 'type' => 101, 'description' => 'link button not pressed' } }]))
        .then
        .to_return(body: JSON.dump([{ 'success' => { 'username' => 'KEY', 'clientkey' => 'HEX' } }]))

      key = described_class.create_app_key(ip, device_type: 'demo#cli', sleeper: ->(_s) {}, clock: -> { 0.0 })

      expect(key).to be_a(PhilipsHue::AppKey)
      expect(key.username).to eq('KEY')
      expect(key.clientkey).to eq('HEX')
    end

    it 'raises LinkButtonNotPressedError once the deadline passes' do
      stub_request(:post, registration)
        .to_return(body: JSON.dump([{ 'error' => { 'type' => 101, 'description' => 'link button not pressed' } }]))

      times = [0.0, 100.0]
      expect do
        described_class.create_app_key(ip, device_type: 'demo#cli', poll_seconds: 30,
                                           sleeper: ->(_s) {}, clock: -> { times.shift })
      end.to raise_error(PhilipsHue::LinkButtonNotPressedError)
    end

    it 'raises HueError for any other pairing error' do
      stub_request(:post, registration)
        .to_return(body: JSON.dump([{ 'error' => { 'type' => 1, 'description' => 'unauthorized' } }]))

      expect { described_class.create_app_key(ip, device_type: 'demo#cli', sleeper: ->(_s) {}, clock: -> { 0.0 }) }
        .to raise_error(PhilipsHue::HueError, /unauthorized/)
    end
  end

  describe '.open' do
    it 'yields a client and closes it afterwards' do
      closed = nil
      described_class.open(bridge_ip: ip, app_key: app_key) do |hue|
        closed = hue
        expect(hue).to be_a(described_class)
      end
      expect(closed.close).to be_nil
    end
  end
end
