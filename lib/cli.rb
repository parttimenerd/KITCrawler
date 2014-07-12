require 'pp'
require 'json'
require 'thor'
require_relative 'services.rb'
require_relative 'cli_add.rb'

def kitgrawler_dir
	`echo ~/.kitcrawler`.strip
end

class CLI < Thor
	class_option :config_file, :type => :string, :aliases => "-c",
			:default => "#{kitgrawler_dir}/config.json",
			:desc => "Use CONFIG_FILE as config file location"
	class_option :auth_file, :type => :string, :aliases => "-a",
			:default => "#{kitgrawler_dir}/auth.json",
			:desc => "Use AUTH_FILE as authentication location"
	class_option :url_cache_file, :type => :string, :aliases => "-u",
			:default => "#{kitgrawler_dir}/url_type_cache.json",
			:desc => "Use URL_CACHE_FILE as url cache file location"
	class_option :debug, :type => :boolean, :default => false, :aliases => "-d",
			:desc => "Print everything to standard out"
	class_option :verbose, :type => :boolean, :default => false, :aliases => "-v",
			:desc => "Print a lot to standard out"
	class_option :warn, :type => :boolean, :default => false, :aliases => "-w",
			:desc => "Print only warnings and errors to standard out"
	class_option :quiet, :type => :boolean, :default => false, :aliases => "-q",
			:desc => "Print nothing to standard out"
	
	desc "fetch [NAME]", "Run fetch job NAME or all jobs"
	def fetch name
		if name == nil
			CLIHelper.new(options).fetch_all
		else
			CLIHelper.new(options).fetch name
		end
	end
	
	desc "add NAME", "Add new job NAME"
	def add name
		CLI_ADD.add_config_ui name, options
	end
	
end

class CLIHelper
	
	def initialize options
		@options = options
		`mkdir -p #{kitgrawler_dir}`
		init_logger
		load_conf_file
		load_auth_file
		load_url_type_cache_file
	end

	def init_logger
		@log = Logger.new STDOUT
		@log_level = Logger::WARN
		@log_level = Logger::DEBUG  if @options[:debug]
		@log_level = Logger::INFO   if @options[:verbose]
		@log_level = Logger::WARN   if @options[:warn]
		@log_level = Logger::UNKOWN if @options[:quiet]
		@log.level = @log_level
		@log.progname = "cli"
	end

	def load_conf_file
		@conf = {}
		return unless File.exists?(@options[:config_file])
		begin
			@conf = JSON.load File.read(@options[:config_file])
		rescue => ex
			@log.fatal "Cannot load config file #{@options[:config_file]}"
			@log.fatal ex
			exit 1
		end
	end
		
	def load_auth_file
		@auth_conf = {}
		return unless File.exists?(@options[:auth_file])
		begin
			@auth_conf = JSON.load File.read(@options[:auth_file])
		rescue => ex
			@log.fatal "Cannot load authentication config file #{@options[:auth_file]}"
			@log.fatal ex
			exit 1
		end
	end
		
	def load_url_type_cache_file
		@url_type_cache = {}
		return unless File.exists?(@options[:url_cache_file])
		begin
			@url_type_cache = JSON.load File.read(@options[:url_cache_file])
		rescue => ex
			@log.fatal "Cannot load url type cache file #{@options[:url_cache_file]}"
			@log.fatal ex
			exit 1
		end
	end
	
	def fetch_all
		begin
			@conf.each_key do |grawl_job|
				fetch grawl_job
			end
		rescue => ex
			@log.fatal "Error grawling configured locations"
			@log.fatal ex
			exit 1
		ensure
			File.open(@options[:url_cache_file], "w") do |f|
				f.puts JSON::pretty_generate @url_type_cache
			end
		end
	end
	
	def fetch job_name
		grawl_location = job_name
		conf = @conf[job_name]
		if conf == nil
			print_job_name_guess job_name
			return
		end
		begin
			service = BaseService::get_service grawl_location, conf, @auth_conf, @log_level, @url_type_cache
			begin
				service.execute
			rescue => ex
				@log.error "Failed executing #{grawl_location}"
				@log.error ex
			end
		rescue => ex
			@log.error "Failed to instantiate #{grawl_location}"
			@log.error ex
		end
	end
	
	def print_job_name_guess job_name
		unless @options[:quiet]
			puts "There is no job '#{job_name}'."
			puts "Maybe you meant one of the following"
			best_n_matches(@conf.keys, job_name, 3).each do |name|
				puts "  #{name}"
			end
		end
	end
	
	def best_n_matches arr, comp, n
		require 'damerau-levenshtein'
		map = {}
		dl = DamerauLevenshtein
		arr.each do |str|
			map[str] = dl.distance(str, comp, 2)
		end
		return arr.sort {|a, b| map[a] <=> map[b] }
	end
end


