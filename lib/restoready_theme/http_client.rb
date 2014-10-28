require 'faraday'
module RestoreadyTheme
  class HttpClient
    attr_accessor :client

    STARTER_ZIP = "https://codeload.github.com/restoready/starter/zip/master"

    def initialize(api_url = nil, api_key = nil)
      @api_key = api_key || config[:api_key]
      @client = Faraday.new(url: api_url ||= config[:api_url]) do |conn|
        conn.request :multipart
        conn.request :url_encoded

        conn.adapter :net_http
      end
    end

    def test?
      ENV['test']
    end

    def asset_list
      response = client.get do |req|
        req.url "#{basepath}"
        req.headers['Authorization'] = token
        req.headers['Accept'] = 'application/json'
      end

      assets = JSON.parse(response.body)["assets"].collect {|a| a['key'] }
      # Remove any .css files if a .css.liquid file exists
      assets.reject{|a| assets.include?("#{a}.liquid") }
    end

    def get_asset(key)
      asset = {}
      response = client.get do |req|
        req.url "#{basepath}/show_by_key?key=#{key}"
        req.headers['Authorization'] = token
        req.headers['Accept'] = 'application/json'
      end

      asset = response.status == 200 ? JSON.parse(response.body)["asset"] : {}
      asset['response'] = response
      asset
    end

    def create_asset(data)
      response = client.post do |req|
        req.url "#{basepath}"
        req.headers['Content-Type'] = 'application/json'
        req.headers['Accept'] = 'application/json'
        req.headers['Authorization'] = token
        req.body = {asset: data}.to_json
      end
      response
    end

    def update_asset(data)
      response = client.put do |req|
        req.url "#{basepath}/#{data[:id]}"
        req.headers['Content-Type'] = 'application/json'
        req.headers['Accept'] = 'application/json'
        req.headers['Authorization'] = token
        req.body = {asset: data}.to_json
      end
      response
    end

    def delete_asset(data)
      response = client.delete do |req|
        req.url "#{basepath}/#{data[:id]}"
        req.headers['Accept'] = 'application/json'
        req.headers['Authorization'] = token
      end
      response
    end

    def get_starter
      source = STARTER_ZIP
      response = client.get do |req|
        req.url "#{source}"
        req.headers['Authorization'] = token
        req.headers['Accept'] = 'application/zip'
        req.headers['Accept-Encoding'] = 'gzip'
      end
      response.status == 200 ? response.body : nil
    end

    def install_starter(theme_name)
      Dir.mktmpdir do |dir|
        File.open("#{dir}/starter-master.zip", 'wb') { |fp| fp.write(get_starter) }
        response = client.post do |req|
          req.url "/api/v1/themes"
          req.headers['Authorization'] = token
          req.body = {theme: {file: Faraday::UploadIO.new("#{dir}/starter-master.zip", 'application/zip'), name: theme_name}}
        end
        theme = response.status == 200 ? JSON.parse(response.body) : {}
        theme.merge!(response: response)
        theme
      end
    end

    def config
      @config ||= if File.exist? 'config.yml'
        config = YAML.load(File.read('config.yml'))
        config
      else
        puts "config.yml does not exist!" unless test?
        {}
      end
    end

    def config=(config)
      @config = config
    end

    def basepath
      @basepath = "/api/v1/themes/#{config[:theme_id]}/assets"
    end

    def ignore_files
      (config[:ignore_files] || []).compact.map { |r| Regexp.new(r) }
    end

    def whitelist_files
      (config[:whitelist_files] || []).compact
    end

    def is_binary_data?(string)
      if string.respond_to?(:encoding)
        string.encoding == "UTF-8"
      else
        ( string.count( "^ -~", "^\r\n" ).fdiv(string.size) > 0.3 || string.index( "\x00" ) ) unless string.empty?
      end
    end

    def check_theme
      response = client.get do |req|
        req.url "/api/v1/tenant"
        req.headers['Authorization'] = token
        req.headers['Accept'] = 'application/json'
      end
      response
    end

    def is_creatable?(asset)
      true
    end

    private

    def token
      "Token token=\"#{@api_key}\""
    end
  end
end
