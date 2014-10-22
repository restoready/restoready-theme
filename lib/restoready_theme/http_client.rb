require 'faraday'
module RestoreadyTheme
  class HttpClient
    attr_accessor :client

    def initialize
      @client = ::Faraday.new(url: "http://#{config[:restoready]}")
    end

    def test?
      ENV['test']
    end

    def asset_list
      # restoready parser chokes on assest listing, have it noop
      # and then use a rel JSON parser.
      response = client.get do |req|
        req.url "#{basepath}"
        req.headers['Authorization'] = token
        req.headers['Accept'] = 'application/json'
      end

      assets = JSON.parse(response.body)["assets"].collect {|a| a['key'] }
      # Remove any .css files if a .css.liquid file exists
      assets.reject{|a| assets.include?("#{a}.liquid") }
    end

    def get_asset_id(key)
      asset = {}
      response = client.get do |req|
        req.url "#{basepath}/id_by_key?key=#{key}"
        req.headers['Authorization'] = token
        req.headers['Accept'] = 'application/json'
      end

      asset['id'] = response.status == 200 ? JSON.parse(response.body)["asset"]["id"] : ''
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
        string.encoding == "US-ASCII"
      else
        ( string.count( "^ -~", "^\r\n" ).fdiv(string.size) > 0.3 || string.index( "\x00" ) ) unless string.empty?
      end
    end

    def check_config
      restoready.get(basepath, headers: headers).code == 200
    end

    def is_creatable?(asset)
      true
    end

    private

      def token
        "Token token=\"#{config[:api_key]}\""
      end
  end
end
