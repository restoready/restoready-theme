require 'thor'
require 'yaml'
YAML::ENGINE.yamler = 'syck' if defined? Syck
require 'abbrev'
require 'base64'
require 'fileutils'
require 'json'
require 'filewatcher'
require 'launchy'
require 'mimemagic'

module RestoreadyTheme
  EXTENSIONS = [
    {mimetype: 'application/x-liquid', extensions: %w(liquid), parents: 'text/plain'},
    {mimetype: 'text/x-liquid', extensions: %w(liquid), parents: 'text/plain'},
    {mimetype: 'application/json', extensions: %w(json), parents: 'text/plain'},
    {mimetype: 'application/js', extensions: %w(map), parents: 'text/plain'},
    {mimetype: 'application/vnd.ms-fontobject', extensions: %w(eot)},
    {mimetype: 'image/svg+xml', extensions: %w(svg svgz)}
  ]

  def self.configureMimeMagic
    RestoreadyTheme::EXTENSIONS.each do |extension|
      MimeMagic.add(extension.delete(:mimetype), extension)
    end
  end

  class Cli < Thor
    include Thor::Actions

    DEFAULT_WHITELIST = %w(layouts/ assets/ config/ snippets/ templates/ locales/)
    TIMEFORMAT = "%H:%M:%S"

    tasks.keys.abbrev.each do |shortcut, command|
      map shortcut => command.to_sym
    end

    desc "configure API_KEY API_URL SITE_URL THEME_ID", "generate a config file for the site to connect to"
    def configure(api_key=nil, api_url=nil, site_url = nil, theme_id=nil)
      config = {api_key: api_key, api_url: api_url, site_url: site_url, theme_id: theme_id}
      create_file('config.yml', config.to_yaml)
      check
    end

    desc "bootstrap API_KEY API_URL SITE_URL THEME_NAME", "bootstrap with Starter to site and configure local directory."
    def bootstrap(api_key=nil, api_url=nil, site_url = nil, theme_name = 'starter')
      config = {:api_key => api_key, :api_url => api_url, :site_url => site_url}

      say("Creating directory named #{theme_name}", :green)
      if File.directory?(theme_name)
        say("Directory #{theme_name} existing, choose another theme name", :red)
        exit
      else
        empty_directory(theme_name)
      end

      say("Registering #{theme_name} theme on #{site_url}", :green)
      theme_info = RestoreadyTheme::HttpClient.new(api_url, api_key).install_starter(theme_name)

      say("Saving configuration to #{theme_name}", :green)
      config.merge!(theme_id: theme_info['id'])
      create_file("#{theme_name}/config.yml", config.to_yaml)

      say("Downloading #{theme_name} assets from RestoReady")
      Dir.chdir(theme_name)
      download()
    end

    desc "open", "open the site in your browser"
    def open(*keys)
      if Launchy.open restoready_theme_url
        say("Done.", :green)
      end
    end

    desc "download FILE", "download all the theme files"
    method_option :quiet, :type => :boolean, :default => false
    method_option :exclude
    def download(*keys)
      assets = keys.empty? ? http_client.asset_list : keys

      if options['exclude']
        assets = assets.delete_if { |asset| asset =~ Regexp.new(options['exclude']) }
      end

      assets.each do |asset|
        download_asset(asset)
        say("Downloaded: #{asset}", :green) unless options['quiet']
      end
      say("Done.", :green) unless options['quiet']
    end

    desc "upload FILE", "upload all theme assets to theme"
    method_option :quiet, type: :boolean, default: false
    def upload(*keys)
      check
      assets = keys.empty? ? local_assets_list : keys
      assets.each do |asset|
        send_asset(asset, options['quiet'])
      end
      say("Done.", :green) unless options['quiet']
    end

    desc "replace FILE", "completely replace restoready theme assets with local theme assets"
    method_option :quiet, type: :boolean, default: false
    def replace(*keys)
      check
      say("Are you sure you want to completely replace your restoready theme assets? This is not undoable.", :yellow)
      if ask("Continue? (Y/N): ") == "Y"
        # only delete files on remote that are not present locally
        # files present on remote and present locally get overridden anyway
        remote_assets = keys.empty? ? (http_client.asset_list - local_assets_list) : keys
        remote_assets.each do |asset|
          delete_asset(asset, options['quiet']) unless http_client.ignore_files.any? { |regex| regex =~ asset }
        end
        local_assets = keys.empty? ? local_assets_list : keys
        local_assets.each do |asset|
          send_asset(asset, options['quiet'])
        end
        say("Done.", :green) unless options['quiet']
      end
    end

    desc "remove FILE", "remove theme asset"
    method_option :quiet, type: :boolean, default: false
    def remove(*keys)
      check
      keys.each do |key|
        delete_asset(key, options['quiet'])
      end
      say("Done.", :green) unless options['quiet']
    end

    desc "watch", "upload and delete individual theme assets as they change, use the --keep_files flag to disable remote file deletion"
    method_option :quiet, type: :boolean, default: false
    method_option :keep_files, type: :boolean, default: false
    def watch
      check
      puts "Surveille le répertoire courant: #{Dir.pwd}"
      watcher do |filename, event|
        filename = filename.gsub("#{Dir.pwd}/", '')

        next if next_watch?(filename, event)
        action = if [:changed, :new].include?(event)
          :send_asset
        elsif event == :delete
          :delete_asset
        else
          raise NotImplementedError, "Unknown event -- #{event} -- #{filename}"
        end

        send(action, filename, options['quiet'])
      end
    end

    desc "systeminfo", "print out system information and actively loaded libraries for aiding in submitting bug reports"
    def systeminfo
      ruby_version = "#{RUBY_VERSION}"
      ruby_version += "-p#{RUBY_PATCHLEVEL}" if RUBY_PATCHLEVEL
      puts "Ruby: v#{ruby_version}"
      puts "Operating System: #{RUBY_PLATFORM}"
      %w(Thor Listen HTTParty Launchy).each do |lib|
        require "#{lib.downcase}/version"
        puts "#{lib}: v" +  Kernel.const_get("#{lib}::VERSION")
      end
    end

    protected

    def config
      @config ||= YAML.load_file 'config.yml'
    end

    def restoready_theme_url
      url = config[:site_url] ||= ""
      url += "/fr?preview_theme_id=#{config[:theme_id]}" if config[:theme_id] && config[:theme_id].to_i > 0
      url
    end

    def http_client
      @http_client = RestoreadyTheme::HttpClient.new
    end

    private

    def watcher
      FileWatcher.new(Dir.pwd).watch() do |filename, event|
        yield(filename, event)
      end
    end

    def local_assets_list
      local_files.reject do |p|
        @permitted_files ||= (DEFAULT_WHITELIST | http_client.whitelist_files).map{|pattern| Regexp.new(pattern)}
        @permitted_files.none? { |regex| regex =~ p } || http_client.ignore_files.any? { |regex| regex =~ p }
      end
    end

    def local_files
      Dir.glob(File.join('**', '*')).reject do |f|
        File.directory?(f)
      end
    end

    def download_asset(key)
      return unless valid?(key)
      asset = http_client.get_asset(key)
      if asset['value']
        # For CRLF line endings
        content = asset['value'].gsub("\r", "")
        format = "w"
      elsif asset['attachment']
        content = Base64.decode64(asset['attachment'])
        format = "w+b"
      end

      FileUtils.mkdir_p(File.dirname(key))
      File.open(key, format) {|f| f.write content} if content
    end

    def send_asset(asset, quiet=false)
      return unless valid?(asset)
      data = {key: asset}
      content = File.read(asset)

      asset_getting = http_client.get_asset(asset)
      if asset_getting['response'].success?
        data.merge!(id: asset_getting['id'])
      end

      if binary_file?(asset) || http_client.is_binary_data?(content)
        content = File.open(asset, "rb") { |io| io.read }
        data.merge!(value: Base64.encode64(content), content_type: MimeMagic.by_path(asset).type)
      else
        data.merge!(value: content, content_type: MimeMagic.by_path(asset).type)
      end

      update_response = show_during("[#{timestamp}] Uploading: #{asset}", quiet) do
        http_client.update_asset(data)
      end
      if update_response.success?
        say("[#{timestamp}] Uploaded: #{asset}", :green) unless quiet
        return
      end

      if !http_client.is_creatable?(asset) || update_response.status != 404
        report_error(Time.now, "Could not upload #{asset}", update_response)
        return
      end

      create_response = show_during("[#{timestamp}] Creating: #{asset}", quiet) do
        http_client.create_asset(data)
      end
      if create_response.success?
        say("[#{timestamp}] #{asset} create", :green) unless quiet
        return
      end
      report_error(Time.now, "Could not created #{asset}", create_response)
    rescue Errno::ENOENT
      say("[#{timestamp}] #{asset} not found in the local repository", :red)
      exit
    end

    def delete_asset(key, quiet=false)
      return unless valid?(key)
      data = {key: key}

      asset_getting = http_client.get_asset(key)
      if asset_getting['response'].success?
        data.merge!(id: asset_getting['id'])
      else
        report_error(Time.now, "#{key} not found.", asset_getting['response'])
      end

      response = show_during("[#{timestamp}] Removing: #{key}", quiet) do
        http_client.delete_asset(data)
      end
      if response.success?
        say("[#{timestamp}] Removed: #{key}", :green) unless quiet
      else
        report_error(Time.now, "Could not deleted #{key}", response)
      end
    end

    def valid?(key)
      return true if DEFAULT_WHITELIST.include?(key.split('/').first + "/")
      say("'#{key}' is not in a valid file for theme uploads", :yellow)
      say("Files need to be in one of the following subdirectories: #{DEFAULT_WHITELIST.join(' ')}", :yellow)
      false
    end

    def binary_file?(path)
      mime = MimeMagic.by_path(path)
      say("'#{path}' is an unknown file-type, uploading asset as binary", :yellow) if mime.nil? && ENV['TEST'] != 'true'
      mime.nil? || (!mime.text? && mime.subtype != "svg+xml")
    end

    def report_error(time, message, response)
      say("[#{timestamp(time)}] Error: #{message}", :red)
      say("Error Details: #{errors_from_response(response)}", :yellow)
    end

    def errors_from_response(response)
      object = {status: response.status}

      errors = JSON.parse(response.body)['errors']

      object[:errors] = case errors
      when NilClass
        ''
      when String
        errors.strip
      else
        errors.values.join(", ")
      end
      object.delete(:errors) if object[:errors].length <= 0
      object
    end

    def show_during(message = '', quiet = false, &block)
      print(message) unless quiet
      result = yield
      print("\r#{' ' * message.length}\r") unless quiet
      result
    end

    def timestamp(time = Time.now)
      time.strftime(TIMEFORMAT)
    end

    def next_watch?(filename, event)
      pref = filename.split('/')[0]
      local_assets_list_tmp = local_assets_list
      local_assets_list_tmp.push(filename) if event == :delete

      return true unless local_assets_list_tmp.include?(filename)
      (pref != 'assets' && pref != 'snippets' && event == :new) || (pref != 'assets' && pref != 'snippets' && event == :delete)
    end

    def check
      response = show_during("[#{timestamp}] Configuration check") do
        http_client.check_theme
      end

      if !response.success?
        report_error(Time.now, "Configuration [FAIL]", response)
        exit
      elsif JSON.parse(response.body)['tenant']['theme_id'] == config[:theme_id].to_i
        say("Configuration [FAIL] : Can't edit an active theme", :red)
        exit
      end
    end
  end
end
RestoreadyTheme.configureMimeMagic
