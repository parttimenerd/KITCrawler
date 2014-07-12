KITCrawler
===================
Fetch lecture PDFs with ease.


It currently supports crawling PDFs for lectures from the studium.kit.edu page,
but can be easily extended to fetch PDFs from other services.

Requirements
-------------------
- ruby (>= 1.9, but 1.8 might also be okay)
- bundler (or install the required gems (see `Gemfile`) manually)
- linux (with curl, might also work on other Unixes)

Install
-------------------
Simply run
```
	gem install kitcrawler
```
to install the gem (it's often a bit behind the repo).

Or run it from source.
```
	git clone https://github.com/parttimenerd/KITCrawler
	cd KITCrawler
	bundle install
``


Usage
-------------------
Run
```
	kitcrawler add NAME
```
to add a new fetch job named `NAME`. This will prompt you to pass an entry URL to the site, etc.

To finally run your jobs use
```
	kitcrawler fetch
```

It also supports some command line parameters, run `kitcrawler` to see an explanation.

License
-------------------
The code is GNU GPL v3 licensed.
