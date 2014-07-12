#!/bin/ruby

require 'logger'
require 'json'
require 'optparse'

module KITCrawler

require_relative 'services.rb'
require_relative 'cli_add.rb'
require_relative 'cli.rb'

	def self.run_cli
		CLI.start ARGV
	end
end