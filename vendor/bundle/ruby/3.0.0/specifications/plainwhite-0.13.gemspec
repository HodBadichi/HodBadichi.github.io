# -*- encoding: utf-8 -*-
# stub: plainwhite 0.13 ruby lib

Gem::Specification.new do |s|
  s.name = "plainwhite".freeze
  s.version = "0.13"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Samarjeet".freeze]
  s.date = "2020-09-24"
  s.email = ["samarsault@gmail.com".freeze]
  s.homepage = "https://thelehhman.com/".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.3.5".freeze
  s.summary = "A portfolio style jekyll theme for writers".freeze

  s.installed_by_version = "3.3.5" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<jekyll>.freeze, [">= 3.7.3"])
    s.add_runtime_dependency(%q<jekyll-seo-tag>.freeze, [">= 2.1.0"])
    s.add_development_dependency(%q<bundler>.freeze, ["> 1.16"])
    s.add_development_dependency(%q<rake>.freeze, ["~> 12.0"])
  else
    s.add_dependency(%q<jekyll>.freeze, [">= 3.7.3"])
    s.add_dependency(%q<jekyll-seo-tag>.freeze, [">= 2.1.0"])
    s.add_dependency(%q<bundler>.freeze, ["> 1.16"])
    s.add_dependency(%q<rake>.freeze, ["~> 12.0"])
  end
end
