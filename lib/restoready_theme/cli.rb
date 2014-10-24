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

    desc "configurer API_KEY RESTOREADY THEME_ID", "Génere un fichier de config."
    def configure(api_key=nil, restoready=nil, theme_id=nil)
      config = {api_key: api_key, restoready: restoready, theme_id: theme_id}
      create_file('config.yml', config.to_yaml)
      check
    end

    desc "open", "Ouvre le theme restoready dans le navigateur."
    def open(*keys)
      if Launchy.open restoready_theme_url
        say("Fini.", :green)
      end
    end

    desc "upload FILE", "Upload tous les assets du thème dans RestoReady."
    method_option :quiet, type: :boolean, default: false
    def upload(*keys)
      check
      assets = keys.empty? ? local_assets_list : keys
      assets.each do |asset|
        send_asset(asset, options['quiet'])
      end
      say("Fini.", :green) unless options['quiet']
    end

    desc "replace FILE", "Remplace complètement le thème en ligne par le thème en locale."
    method_option :quiet, type: :boolean, default: false
    def replace(*keys)
      check
      say("Êtes-vous sur de vouloir remplacer entièrement le thème en ligne par celui en locale? Cette action est irréversible.", :yellow)
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
        say("Fini.", :green) unless options['quiet']
      end
    end

    desc "remove FILE", "Supprime les assets voulus du thème."
    method_option :quiet, type: :boolean, default: false
    def remove(*keys)
      check
      keys.each do |key|
        delete_asset(key, options['quiet'])
      end
      say("Fini.", :green) unless options['quiet']
    end

    desc "watch", "Surveille tous changements dans le thème locale et reporte ces changements en ligne, utiliser le flag --keep_files pour désactiver la suppréssion des fichiers."
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
          raise NotImplementedError, "Évenement inconu -- #{event} -- #{filename}"
        end

        send(action, filename, options['quiet'])
      end
    end

    desc "systeminfo", "Affiche les informations système et les librairies chargées pour soumettre les rapports de bug."
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
      url = config[:restoready]
      url += "?preview_theme_id=#{config[:theme_id]}" if config[:theme_id] && config[:theme_id].to_i > 0
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

    def send_asset(asset, quiet=false)
      return unless valid?(asset)
      data = {key: asset}
      content = File.read(asset)

      asset_getting = http_client.get_asset_id(asset)
      if asset_getting['response'].success?
        data.merge!(id: asset_getting['id'])
      end

      if binary_file?(asset) || http_client.is_binary_data?(content)
        content = File.open(asset, "rb") { |io| io.read }
        data.merge!(value: Base64.encode64(content), content_type: MimeMagic.by_path(asset).type)
      else
        data.merge!(value: content, content_type: MimeMagic.by_path(asset).type)
      end

      update_response = show_during("[#{timestamp}] Mise à jour: #{asset}.", quiet) do
        http_client.update_asset(data)
      end
      if update_response.success?
        say("[#{timestamp}] #{asset} mise à jour.", :green) unless quiet
        return
      end

      # if !http_client.is_creatable?(asset) || update_response.code != 404
      if !http_client.is_creatable?(asset) || update_response.status != 404
        report_error(Time.now, "Impossible de mettre à jour #{asset}.", update_response)
        return
      end

      create_response = show_during("[#{timestamp}] Création: #{asset}.", quiet) do
        http_client.create_asset(data)
      end
      if create_response.success?
        say("[#{timestamp}] #{asset} créé.", :green) unless quiet
        return
      end
      report_error(Time.now, "Impossible de créer #{asset}.", create_response)
    end

    def delete_asset(key, quiet=false)
      return unless valid?(key)
      data = {key: key}
      data.merge!(id: http_client.get_asset_id(key)['id'])

      response = show_during("[#{timestamp}] Suppréssion: #{key}.", quiet) do
        http_client.delete_asset(data)
      end
      if response.success?
        say("[#{timestamp}] #{key} supprimé.", :green) unless quiet
      else
        report_error(Time.now, "Impossible de supprimer #{key}.", response)
      end
    end

    def valid?(key)
      return true if DEFAULT_WHITELIST.include?(key.split('/').first + "/")
      say("'#{key}' n'est pas un fichier valide pour la mise à jour.", :yellow)
      say("Les fichiers ont besoin de se trouver dans les sous dossiers #{DEFAULT_WHITELIST.join(' ')}.", :yellow)
      false
    end

    def binary_file?(path)
      mime = MimeMagic.by_path(path)
      say("'#{path}' est un file-type inconnu, mise à jour de l'asset sous forme binaire.", :yellow) if mime.nil? && ENV['TEST'] != 'true'
      mime.nil? || (!mime.text? && mime.subtype != "svg+xml")
    end

    def report_error(time, message, response)
      say("[#{timestamp(time)}] Error: #{message}", :red)
      say("Details d'erreur : #{errors_from_response(response)}", :yellow)
      exit
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
      response = show_during("[#{timestamp}] Vérification de la configuration.") do
        http_client.check_theme
      end

      if !response.success?
        report_error(Time.now, "Configuration [FAIL]", response)
        exit
      elsif JSON.parse(response.body)['tenant']['theme_id'] == config[:theme_id].to_i
        say("Configuration [FAIL] : Le thème id renseigné ne doit pas être celui actif en ligne.", :red)
        exit
      end
      say("Configuration [OK]", :green)
    end
  end
end
RestoreadyTheme.configureMimeMagic
