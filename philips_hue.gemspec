# frozen_string_literal: true

require_relative 'lib/philips_hue/version'

Gem::Specification.new do |spec|
  spec.name          = 'philips_hue'
  spec.version       = PhilipsHue::VERSION
  spec.authors       = ['Michelle Pellon']
  spec.email         = ['122621769+michellepellon@users.noreply.github.com']
  spec.summary       = 'Ruby library for the Philips Hue CLIP API v2.'
  spec.description   = 'The Philips Hue Ruby library provides convenient access to the local Philips Hue ' \
                       'CLIP API v2 from applications written in the Ruby language. It can discover a ' \
                       'Bridge, pair to obtain an application key, read and control lights and rooms, ' \
                       'and subscribe to the Bridge event stream.'
  spec.homepage      = 'https://github.com/michellepellon/philips_hue.rb'
  spec.license       = 'ISC'
  spec.required_ruby_version = '>= 4.0.0'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'documentation_uri' => 'https://rubydoc.info/gems/philips_hue',
    'rubygems_mfa_required' => 'true'
  }

  # Specify which files should be added to the gem when it is released
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{\A(?:test|spec|features|\.github)/})
    end
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Dependencies
  spec.add_development_dependency 'rake', '13.2.1'
  spec.add_development_dependency 'rspec', '3.13.0'
  spec.add_development_dependency 'rubocop', '1.75.2'
  spec.add_development_dependency 'webmock', '3.25.1'
end
