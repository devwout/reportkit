# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
 
require 'reportkit/version'
 
Gem::Specification.new do |s|
  s.name        = "reportkit"
  s.version     = Reportkit::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Ewout van Troostenberghe"]
  s.email       = ["e@ewout.name"]
  s.homepage    = "https://github.com/devwout/reportkit"
  s.summary     = "<todo>"
  s.description = "<todo>"
 
  s.add_dependency "activerecord", "~>2.3.5"
  s.add_dependency "arel-compat", "~>0.4.0"
  s.add_dependency "filterkit"

  s.add_development_dependency "rspec"
 
  s.files        = Dir.glob("{bin,lib}/**/*")
  s.require_path = 'lib'
end

