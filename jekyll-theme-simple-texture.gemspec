# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "simple-texture"
  spec.version       = "0.2.2"
  spec.authors       = ["Oscao Chaser"]
  spec.email         = ["406082341@qq.com"]

  spec.summary       = %q{A gem-based responsive simple texture styled Jekyll theme.}
  spec.homepage      = "https://github.com/OscaoChaser/OscaoChaser.github.io"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").select { |f| f.match(%r{^(assets|_layouts|_includes|_sass|LICENSE|README)}i) }

  spec.add_runtime_dependency "jekyll", "= 3.5.2"
  spec.add_runtime_dependency "jekyll-feed", "~> 0.9.2"
  spec.add_runtime_dependency "jekyll-redirect-from", "~> 0.12.1"
  spec.add_runtime_dependency "jekyll-seo-tag", '~> 2.2', '>= 2.2.3'
  spec.add_runtime_dependency "jekyll-sitemap", '~> 1.1', '>= 1.1.1'

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"
end
