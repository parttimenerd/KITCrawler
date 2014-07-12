require 'pp'
require 'json'
require_relative 'services.rb'

module CLI_ADD
	
	require 'highline/import'
	
	def self.add_config_ui name, options
		CLIHelper.new options
		config_json = JSON.load File.read(options[:config_file])
		auth_json = JSON.load File.read(options[:auth_file])
		say("Configure #{name}")
		name = check_name name, config_json
		conf = {}
		conf["entry_url"] = ask_entry_url
		conf["type"] = ask_type conf
		conf["pdfs"] = ask_pdfs conf
		if BaseService.get_services["needs_auth"]
			conf["auth"] = ask_auth name, conf, auth_json
		end
		config_json[name] = conf
		say "This configuration is placed into your config files."
		say "Your config file is #{options[:config_file]}."
		say "Your authentication config file is #{options[:auth_file]}."
		File.open(options[:config_file], "w") do |f|
			f.puts JSON.pretty_generate config_json
		end
		File.open(options[:auth_file], "w") do |f|
			f.puts JSON.pretty_generate auth_json
		end
	end

	def self.check_name name, config_json
		names = config_json.keys
		while names.include? name
			name = ask "Fetch job name (#{name} is already in use)? "
		end
		return name
	end

	def self.ask_entry_url
		return ask_url "Entry point url? "
	end

	def self.ask_type conf
		default = BaseService::get_service_for_url conf["entry_url"]
 		choose do |menu|
			menu.prompt = "Service type [#{default}]? "
			menu.default = default
			BaseService::get_services.each do |name, service|
				menu.choices("#{name} (#{service["description"]})") do |q|
					say "You've choosen '#{name}'."
					return name
				end
			end
		end
	end

	def self.ask_pdfs conf
		return {
			"src_folder" => ask_non_empty("Source folder url (relative to entry url directory if starts with dot)? "),
			"dest_folder" => ask_non_empty("Destination folder (relative to $HOME)? "),
			"download_once" => ask_yes_no(
				"Dowload a PDF only once (ignore changes, boost performance)? ", "yes"
			) == "yes"
		}
	end

	def self.ask_auth name, conf, auth_json
		is_studium_kit = conf["type"] == "studium_kit"
		has_s_kit_auth = auth_json["studium_kit"] != nil
		has_name_auth = auth_json[name] != nil
		default = ""
		if ask_yes_no("Auth: Use existing user/password configuration? ", is_studium_kit && has_s_kit_auth ? "yes" : "no") == "yes"
			if is_studium_kit && has_s_kit_auth
				default = "studium_kit"
			end
			choose do |menu|
				menu.prompt = "Auth: Which configuration? "
				menu.default = default unless default.empty?
				auth_json.each do |name, config|
					menu.choices("#{name} (user: #{config["user"]})") do |q|
						say "Auth: You've chosen '#{name}'."
						return name
					end
				end
			end
		else
			auths = auth_json.keys
			auth_name = ""
			if is_studium_kit && !has_s_kit_auth
				default = "studium_kit"
				auth_name = ask "Auth: Configuration name [studium_kit]? " do |q|
					q.default = studium_kit
				end
			elsif not has_name_auth
				auth_name = ask "Auth: Configuration name [#{name}]? " do |q|
					q.default = name
				end
			else
				auth_name = ask_non_empty "Auth: Configuration name? "
			end
			begin
				auth_json[auth_name] = ask_user_pass
			end while ask_yes_no("Auth: Confirm that you're credentials are right. Are they? ", "yes") == "no"
			return auth_name
		end
	end

	def self.ask_user_pass
		user = ask "Auth: User name? "
		pass = ""
		pass2 = ""
		begin
			pass = ask("Auth: Password? ") { |q| q.echo = "x" }
			pass2 = ask("Auth: Retype it ") { |q| q.echo = "x" }
		end while pass != pass2
		return {
			"user" => user,
			"pass" => pass
		}
	end

	def self.ask_url question
		str = ""
		while str.strip.length < 4
			str = ask(question) || ""
		end
		return str.strip
	end

	def self.ask_non_empty question
		str = ""
		while str.strip.empty?
			str = ask(question) || ""
		end
		return str.strip
	end

	def self.ask_yes_no question, default = "yes"
		choose do |menu|
			menu.layout = :one_line
			menu.prompt = "#{question} [#{default}] "
			menu.default = default
			menu.choices(:yes, :no) do |q|
				return q.to_s
			end
		end
	end
end