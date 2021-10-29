require "net/https"
require "uri"
require "resolv"
require "logger"

require_relative "./error"
require_relative "./settings"

module Reverie
  class Base
    attr_accessor :log, :args, :conf, :settings

    def initialize(logger = Logger.new($stdout))
      @settings = Settings.new
      init_logger
      pp settings
    end

    def init_logger
      @log = Logger.new($stdout)
      @log.level = settings.debug ? Logger::DEBUG : Logger::INFO
    end

    def update_dns
      begin
        check_last_update! and
          check_ip! and
          replace_record! settings.record, settings.ip and
          log.info "#{settings.record} updated to #{settings.ip}" and
          settings.save!
      rescue Reverie::Error => e
        log.debug e.message
      end
    end

    private

    def check_last_update!
      last_update = Time.now - (settings.updated_at || Time.mktime(0))

      raise UpdateFrequencyError, last_update if last_update < settings.min_frequency

      true
    end

    def check_ip!
      raise IPFetchError if (ip = get_ip).nil?

      if ip != settings.ip
        settings.ip = ip
        settings.updated_at = Time.now
        true
      else
        log.debug "not updating #{settings.record}"
        false
      end
    end

    def replace_record!(record, ip)
      raise InvalidRecordError unless record
      raise InvalidIP unless ip

      status, res = api_call(:list_records)
      raise ListRecordError, res unless status == "success"

      dh_record = res.detect { |r| r[:record] == record }

      if dh_record
        raise RecordNotEditable if dh_record[:editable] != 1

        status, res = api_call(
          :remove_record,
          record: record,
          type: dh_record[:type],
          value: dh_record[:value]
        )

        log.debug "removed #{record}"
      else
        log.debug "#{record} not found"
      end

      status, res = api_call(
        :add_record,
        record:  record,
        type:    "A",
        value:   ip,
        comment: "Reverie (#{ Time.now })"
      )

      raise AddRecordError, res unless status == "success"
    end

    def get_ip
      log.debug "connecting to #{settings.ip_url}"
      ip = Net::HTTP.get_response(URI(settings.ip_url)).body.strip
      log.debug "got #{ip}"
      ip if ip =~ Resolv::IPv4::Regex
    rescue Net::ReadTimeout
      log.warn :timeout, "IP Lookup", settings.ip_url
    end

    def api_call(cmd, args = {})
      args = args.reverse_merge(
        key: settings.key,
        record: settings.record,
        format: "yaml",
        cmd: "dns-#{cmd}",
        unique_id: SecureRandom.uuid
      )

      uri = URI(settings.domain_api_url)
      log.info(uri.query = URI.encode_www_form(args))

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = 1
      http.set_debug_output($stdout)
      req = http.request(Net::HTTP::Get.new("/"))
      # req = Net::HTTP.start(
      #   uri.host,
      #   uri.port,
      #   settings.openssl_options
      # ) do |http|
      #   http.get uri
      # end

      res = YAML.load(req.body).with_indifferent_access
      log.info "#{args[:cmd]}: #{res[:result]}"

      req.close
      [res[:result], res[:data]]
    rescue Net::ReadTimeout
      log.warn "API (#{uri}) timed out on #{args[:cmd]}"
    end
  end
end
