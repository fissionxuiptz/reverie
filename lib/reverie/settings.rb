require "active_support/core_ext/hash/indifferent_access"
require "optparse"
require "yaml"

module Reverie
  class Settings
    attr_reader :__settings

    def initialize
      @__settings = {
        config: Pathname(ENV["HOME"] || "/").join(*%w[.config reverie reverie.yml]),
        min_frequency: 600,
        domain_api_url: "https://api.dreamhost.com",
        ip_url: "http://myexternalip.com/raw",
        openssl_options: {
          use_ssl: true,
          ssl_version: :TLSv1_2,
          verify_mode: OpenSSL::SSL::VERIFY_PEER
        }
      }.with_indifferent_access

      resolve_commandline
      __settings.reverse_merge! resolve_config_file
    end

    def save!
      File.open(config, "w", 0600) do |f|
        f.write @__settings.except(:config).to_hash.to_yaml
      end
    end

    %i[
      config key record ip debug updated_at
      min_frequency domain_api_url ip_url openssl_options
    ].each do |method_name|
      define_method(method_name) { @__settings[method_name] }
      define_method("#{method_name}=") { |val| @__settings[method_name] = val }
    end

    private

    def resolve_commandline
      OptionParser.new do |opts|
        opts.on("-cCONFIG", "--config=CONFIG", "Path to configuration file") do |config|
          self.config = config
        end

        opts.on("-kKEY", "--key=KEY", "Dreamhost API Key") do |key|
          self.key = key
        end

        opts.on("-rRECORD", "--record=RECORD", "DNS record (eg. `www.softwaremojo.com`)") do |record|
          self.record = record
        end

        opts.on("-iIP", "--ip=IP", "Last known IP address") do |ip|
          self.ip = ip
        end

        opts.on("-d", "--debug", "Debug") do
          self.debug = true
        end
      end.parse!
    end

    def resolve_config_file
      return {} unless File.exist? config

      YAML.load File.read(config)
    end
  end
end
