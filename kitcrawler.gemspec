Gem::Specification.new do |s|
	s.name        = 'kitcrawler'
  	s.version     = '0.1.0'
    s.date        = '2014-07-12'
	s.summary     = "Fetch lecture PDFs with ease"
	s.description = <<-EOF
	Crawl lecture websites and fetch the PDFs automatically. 
	It currently supports the studium.kit.edu and other HTTP password protected sites.
	EOF
	s.authors     = ["Johannes Bechberger"]
	s.email       = 'me@mostlynerdless.de'
	s.files       = ["lib/kitcrawler.rb", "lib/services.rb", "lib/cli.rb", "lib/cli_add.rb"]
	s.homepage    = "https://github.com/parttimenerd/KITCrawler"
	s.license     = 'GPL v3'
	s.executables  << 'kitcrawler'
	s.requirements << 'Linux (other UNIXes might also work)'
	s.requirements << 'curl'
	s.extra_rdoc_files = ['README.md']
	s.add_runtime_dependency 'nokogiri', '>= 1.6.1'
	s.add_runtime_dependency 'highline', '>= 1.6.0'
	s.add_runtime_dependency 'thor', '>= 0.19.0'
	s.add_runtime_dependency 'damerau-levenshtein', '>= 1.0.0'
	s.required_ruby_version = '>= 1.8.6'
end

