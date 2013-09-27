# coding: utf-8
lib = File.expand_path '../lib', __FILE__
$LOAD_PATH.unshift lib unless $LOAD_PATH.include? lib
require 'reverie'

Gem::Specification.new do |s|
  s.name        = 'reverie'
  s.version     = Reverie::VERSION
  s.date        = Time.new.strftime '%Y-%m-%d'
  s.author      = 'Fission Xuiptz'
  s.email       = 'fissionxuiptz@softwaremojo.com'
  s.homepage    = 'http://github.com/fissionxuiptz/reverie'
  s.license     = 'MIT'

  s.summary     = 'Dreamhost DNS updater'
  s.description = 'A ruby script to update Dreamhost DNS'

  s.files       = `git ls-files`.split $/
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename f }
  s.test_files  = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ['lib']

  s.add_runtime_dependency 'configliere', '~> 0.4'
end
