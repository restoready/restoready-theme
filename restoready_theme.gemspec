# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "restoready_theme/version"

Gem::Specification.new do |s|
  s.name        = "restoready_theme"
  s.version     = RestoreadyTheme::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Derivery Damien"]
  s.email       = ["damien@restoready.com"]
  s.homepage    = "https://github.com/restoready/restoready-theme"
  s.summary     = %q{Command line tool for developing themes}
  s.description = %q{Command line tool to help with developing RestoReady themes. Provides simple commands to download, upload and delete files from a theme. Also includes the watch command to watch a directory and upload files as they change.}
  s.license     = 'MIT'

  s.rubyforge_project = "restoready_theme"
  s.add_dependency('thor', '~> 0.14')
  s.add_dependency('faraday', '~> 0.9')
  s.add_dependency('json', '~> 1.8')
  s.add_dependency('mimemagic', '~> 0')
  s.add_dependency('filewatcher', '~> 0')
  s.add_dependency('launchy', '~> 0')

  s.add_development_dependency 'rake', '~> 0'
  s.add_development_dependency 'rspec', '~> 3'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ['lib']
end
