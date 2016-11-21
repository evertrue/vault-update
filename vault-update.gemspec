# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vault-update/version'

Gem::Specification.new do |spec|
  spec.name          = 'vault-update'
  spec.version       = VaultUpdate::VERSION
  spec.authors       = ['Eric Herot']
  spec.email         = ['devops@evertrue.com']

  spec.summary       = 'Safely updates a Vault secret while also keeping history.'
  # spec.description   = 'TODO: Write a longer description or delete this line.'
  spec.homepage      = 'https://evertrue.github.io'
  spec.license       = 'Apache'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'diffy'
  spec.add_dependency 'trollop'
  spec.add_dependency 'vault'
  spec.add_dependency 'colorize'

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
