require 'nokogiri'
require 'cgi'
require 'pp'
require 'uri'
require 'logger'
require 'set'
require 'time'
require 'uri'
require 'json'

class BaseService

	@conf = {}
	@auth_app = ""
	@file_header_cache = {} #url => splitted HTTP header lines
	@processed_pdfs = {} #url => dest file
	@name = ""
	@@log
	@@service_classes = {}
	@type_cache = {}
	@uri_cache = {} #url => URI
	
	def initialize name, conf, auth_conf = {}, log_level = Logger::WARN, url_type_cache = {}
		@base_dir = `echo ~`.strip
		@uri_cache = {}
		@file_header_cache = {}
		@type_cache = url_type_cache
		@processed_pdfs = {}
		@name = name
		@log = Logger.new(STDOUT)
		@log.progname = name
		@log.level = log_level
		
		@conf = {
			"type" => "base",
			"exclude_file_endings" => [".css", ".js", ".txt", ".rss", ".atom"],
			"access_pause" => { #in seconds
				"min" => 0.1,
				"max" => 0.3
			},
			"pdfs" => {
				"src_folder" => "abc.de/a", #is relative to entry_url base dir if starts with dot
				"dest_folder" => "abcd", 
		        "download_once" => true
			},
			"cookie_jar" => "cookies.txt",
			"user_agent" => "Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:30.0) Gecko/20100101 Firefox/30.0",
			"entry_url" => "",
			"auth" => "base" #references auth conf or {"user" => "", "pass" => ""}
		}
		temp_conf = @conf.merge conf
		unless conf["pdfs"] == nil
			temp_conf["pdfs"] = @conf["pdfs"].merge conf["pdfs"]
		end
		@conf = temp_conf
		if @conf["auth"].is_a? String
			@conf["auth"] = auth_conf[@conf["auth"]]
			@log.debug "Load auth from auth config #{auth_conf}"
		end
		
		if @conf["pdfs"]["src_folder"].start_with? "."
			entry_uri = get_uri @conf["entry_url"]
			entry_path_url = entry_uri.scheme + "://" + entry_uri.host + File.dirname(entry_uri.path)
			@conf["pdfs"]["src_folder"] = "#{entry_path_url}/#{@conf["pdfs"]["src_folder"]}"
			@log.info "Source folder is #{@conf["pdfs"]["src_folder"]}"
		end
		
		src_url_parsed = URI.parse(@conf["pdfs"]["src_folder"])
		@conf["pdfs"]["src_path"] = src_url_parsed.path
		@conf["pdfs"]["src_host"] = src_url_parsed.host
		@log.info "Start authentication"
		authenticate
		@log.info "Authentication completed"
	end
	
	def self.get_service name, conf, auth_conf={}, log_level = Logger::WARN, url_type_cache = {}
		service = @@service_classes[conf["type"]]
		if service == nil
			raise "Unknown service #{conf["type"]}"
		else
			service["class"].new name, conf, auth_conf, log_level, url_type_cache
		end
	end
	
	def authenticate
		""
	end

	def execute
		@log.info "Start grawling #{@conf["entry_url"]}"
		parse_html_page @conf["entry_url"]
		@log.info "Completed grawling #{@conf["entry_url"]}"
	end

	def parse_html_page url, url_cache = Set.new
		url = url_chomp url
		return if url_cache.member?(url)
		url_cache.add url
		@log.info "Fetch and parse #{url}"
		html = ""
		begin
			html = fetch_url url
			access_pause_sleep
		rescue => ex
			@log.error "Cannot fetch #{url}"
			@log.error ex
			return
		end
		links = parse_html url, html
		links["html"].each do |html_link|
			parse_html_page html_link, url_cache
		end
		links["pdf"].each do |pdf_link|
			process_pdf pdf_link
		end
	end

	##
	#Executes curl to fetch the requested url
	#@param url requested url
	#@param output_file output destination, if nil the output gets returned by
	#this method
	def fetch_url url, output_file=nil, curl_params=""
		curl_params = "#{@auth_app} #{curl_params} --silent --user-agent \"#{@conf["user_agent"]}\""
		curl_params += " -b #{@conf["cookie_jar"]} -c #{@conf["cookie_jar"]} -L -o \"#{output_file || "-"}\" #{url}"
		@log.debug "Call curl on #{url}"
		@log.debug "Curl parameters '#{curl_params}'"
		`cd #{@base_dir}; curl #{curl_params}`
	end

	def post url, params, output_file=nil, curl_params=""
		param_arr = []
		params.each do |key, value|
			param_arr << "#{CGI::escape(key)}=#{CGI::escape(value)}"
		end
		param = param_arr.join "&"
		begin
			fetch_url url, output_file, "#{curl_params} --data \"#{param}\""
		rescue => ex
			@log.error "Failed to POST #{url} with data #{params}"
			@log.error ex
			""
		end
	end

	def parse_html url, html
		doc = nil
		links = {'pdf' => [], 'html' => []}
		begin
			doc = Nokogiri::HTML html
		rescue => ex
			@log.error "Parsing html from url #{url} failed"
			return links
		end
		doc.css('a[href]').each do |link|
			begin
				link_url = url_chomp(URI.join(url, link.attributes["href"]).to_s).to_s
				@log.debug "Process link #{link_url}"
				if is_pdf_url link_url
					links['pdf'] << link_url 
					@log.debug "#{link_url} is pdf"
				elsif is_html_url link_url
					links['html'] << link_url
					@log.debug "#{link_url} is html"
				end
			rescue => ex
				@log.debug "Omit #{link}"
			end
		end
		return links
	end
	
	def get_field_value html, field
		doc = nil
		begin
			doc = Nokogiri::HTML html
		rescue => ex
			@log.error "Parsing html failed"
			@log.error ex
			return ""
		end
		value = ""
		doc.css("##{field}").each do |link|
			value = link.attributes["value"].to_s
		end
		return value
	end
	
	def get_type url
		if is_excluded url
			return ""
		end
		if @type_cache[url] == nil
			if url.upcase.end_with?(".PDF") || 
				get_file_header(url)["Content-Type"].start_with?("application/pdf", "application/x-pdf")
				@type_cache[url] = "pdf"
			elsif get_file_header(url)["Content-Type"].start_with?("text/html")
				@type_cache[url] = "html"
			else
				@type_cache[url] = ""
			end
		end
		return @type_cache[url]
	end

	def is_pdf_url url
		get_type(url) == "pdf"
	end

	def is_html_url url
		get_type(url) == "html" 
	end
	
	def is_excluded url
		parsed_url = get_uri url
		parsed_url.path.send(:start_with?, @conf["exclude_file_endings"]) ||
				parsed_url.host != @conf["pdfs"]["src_host"] ||
				!parsed_url.path.start_with?(@conf["pdfs"]["src_path"])
	end
	
	def access_pause_sleep
		min = @conf["access_pause"]["min"]
		max = @conf["access_pause"]["max"]
		duration = Random.rand() * (max - min) + min
		@log.debug "Sleep #{duration} seconds to behave a bit more human"
		sleep duration
	end

	def get_file_header url
		url = url_chomp url
		if @file_header_cache[url] == nil
			header = fetch_url url, "-", "-I"
			lines = header.split("\r\n").map {|val| val.split(": ") }
			response = {}
			lines.each {|arr| response[arr[0]] = arr[1] }
			@file_header_cache[url] = response
			@log.info "Fetch header of #{url}"
			access_pause_sleep
		end
		return @file_header_cache[url]
	end

	def get_path_url url
		parsed = get_uri url
		parsed.path + (parsed.query != "" ? "?#{parsed.query}": "")
	end

	def process_pdf url
		url = url_chomp url
		return unless @processed_pdfs[url] == nil
		@log.info "Process pdf #{url}"
		dest = get_dest_path url
		if not @conf["pdfs"]["download_once"]
			header_date = get_file_header(url)["Last-Modified"]
			header_time = header_date != nil ? Time.parse(header_date).to_i : Time.now.to_i
			file_time = File.exists?(dest) ? File.mtime(dest).to_i : 0
			@log.info "Process pdf #{url} with mtime #{header_time}, file mtime #{file_time}"
			if file_time >= header_time
				@log.info "Destination file #{dest} isn't younger => no download"
				return
			end
		elsif File.exists? dest
			@log.info "Destination file exists => no download"
			return
		end
		`mkdir -p "#{File.dirname(dest)}"` unless File.exists? File.dirname(dest)
		@log.info "Destination file #{dest} is older => download"
		begin
			@log.debug(fetch_url url, dest)
		rescue => ex
			@log.error "Downloading #{url} failed"
			@log.error ex
		end
		@processed_pdfs[url] = dest
		access_pause_sleep
	end
	
	def get_dest_path url
		url_path = get_uri(url).path
		src_path = @conf["pdfs"]["src_path"]
		dest_folder = @conf["pdfs"]["dest_folder"]
		dest_folder + "/" + url_path.slice(src_path.length, url_path.length - src_path.length)
	end

	def self.add_service_class name, description, service_class, needs_auth = true, url_regex = nil
		@@service_classes[name] = { 
			"class" => service_class,
			"url_regex" => url_regex,
			"description" => description,
			"needs_auth" => needs_auth
		}
	end
	
	def get_uri url
		if @uri_cache[url] == nil
			@uri_cache[url] = URI.parse url
		end
		return @uri_cache[url]
	end
	
	def url_chomp url
		uri = get_uri url
		uri.scheme + "://" + uri.host + uri.path + (uri.query != nil ? "?#{uri.query}" : "")
	end
	
	def self.get_services
		@@service_classes.clone
	end
	
	def self.get_service_for_url url
		@@service_classes.each do |name, service|
			unless service["url_regex"] == nil && service["url_regex"] =~ url
				return name 
			end
		end
		return "base"
	end	
	
	self.add_service_class "base", "without any authentication", self, false, nil

end

class SecuredService < BaseService

	def authenticate
		unless @conf["auth"] != nil && @conf["auth"]["user"] != nil && @conf["auth"]["pass"]
			raise "No authentication (user name and password) given"
		end
		_authenticate
	end
	
	def _authenticate
	end

end

class StudiumKITService < SecuredService
	
	def _authenticate
		login_url = "https://studium.kit.edu/_layouts/login.aspx?ReturnUrl=%2f"
		html = nil
		post_html = nil
		begin 
			html = fetch_url login_url
			params = {
				"ctl00$PlaceHolderMain$Login$UserName" => @conf["auth"]["user"],
				"ctl00$PlaceHolderMain$Login$password" => @conf["auth"]["pass"],
				"ctl00$PlaceHolderMain$Login$loginbutton" => "Anmelden",
				"__VIEWSTATE" => get_field_value(html, "__VIEWSTATE"),
				"__EVENTVALIDATION" => get_field_value(html, "__EVENTVALIDATION"),
				"__spDummyText1" => "",
				"__spDummyText2" => ""
			}
		rescue => ex
			@log.fatal ex
			raise "Fetching and parsing login page failed"
		end
		begin
			post_html = post login_url, params
		rescue => ex
			@log.fatal ex
			raise "POST request to login page failed"
		end
		if post_html == html
			raise "Authentication failed, wrong user name or password"
		end
	end
	
	self.add_service_class "studium_kit", "studium.kit.edu service", self, true, /studium\.kit\.edu/
	
end

class HTTPAuthService < SecuredService
	
	def _authenticate
		@auth_app = "-u #{URI::escape @conf["auth"]["user"]}:#{URI::escape @conf["auth"]["pass"]}"
	end
	
	self.add_service_class "http_auth", "http authenticated service", self, true, nil
	
end
