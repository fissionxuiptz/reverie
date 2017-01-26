# Reverie

# Ported from Ian McKellar's dreamhost-ddns
# https://github.com/ianloic/dreamhost-ddns

require 'net/http'
require 'resolv'
require 'logger'
require 'yaml'
require 'configliere'

require_relative 'configliere'
require_relative 'version'

Settings.use :commandline, :config_file, :define

class Reverie
  attr_accessor :log, :conf, :args

  DH_URI = URI 'https://api.dreamhost.com/'
  IP_URI = URI 'http://myexternalip.com/raw'
  CONF   = Configliere::DEFAULT_CONFIG_LOCATION[:user_config][:reverie]

  OPENSSL_OPTIONS = {
    use_ssl:     true,
    ssl_version: :TLSv1,
    verify_mode: OpenSSL::SSL::VERIFY_PEER
  }

  Settings.define :conf,
                  type:        :filename,
                  description: 'The location of the configuration file',
                  default:     CONF

  Settings.define :log,
                  type:        :filename,
                  description: 'The location of the log file'

  def self.update_dns
    Reverie.new.tap { |r| r.update_dns }
  end

  def initialize
    Settings.resolve!

    init_conf
    init_log
    init_args
  end

  def init_args
    @args = {
      key:    Settings[:key],
      record: Settings[:record],
      format: 'yaml'
    }
  end

  def init_conf
    @conf = Settings.delete('conf') || CONF
    Settings.read conf
  end

  def init_log
    @log = Logger.new(Settings.log || STDOUT)
    log.level = Settings.delete('debug') ? Logger::DEBUG : Logger::INFO
    Settings.delete('log') unless Settings.log
  end

  def settings
    Settings
  end

  def update_dns
    last_update = Time.now - (Settings[:updated_at] || Time.mktime(0))

    if (last_update < 900   and log.debug "too soon, updated #{last_update}s ago") ||
       ((ip = get_ip).nil?  and log.debug "get_ip failed") ||
       (ip == Settings[:ip] and log.debug "not updating #{Settings[:record]}") ||
       (!replace_record Settings[:record], ip and log.debug "replace_record failed")
      return
    end

    Settings.merge! ip: ip, updated_at: Time.now
    Settings.save! conf
    log.info "#{Settings[:record]} updated to #{ip}"
  end

  def replace_record(record, ip)
    return false unless record && ip

    status, res = api_call :list_records
    return false unless status == 'success'

    res.detect { |r| r['record'] == record && r['editable'] == 1 }.tap do |r|
      api_call :remove_record,
               record: record,
               type:   r['type'],
               value:  r['value'] if r
    end

    status, _ = api_call :add_record,
                         record:  record,
                         type:    'A',
                         value:   ip,
                         comment: "Reverie (#{ Time.now })"
    status == 'success'
  end

  def get_ip
    log.debug "connecting to #{IP_URI}"
    ip = Net::HTTP.get_response(IP_URI).body.strip
    log.debug "got #{ip}"
    ip if ip =~ Resolv::IPv4::Regex
  rescue Net::ReadTimeout
    log.warn :timeout, 'IP Lookup', IP_URI
  end

  private

  def api_call(cmd, args = {})
    a = @args.merge(cmd: "dns-#{ cmd }", unique_id: SecureRandom.uuid)
    a.merge! args

    log.info(DH_URI.query = URI.encode_www_form(a))

    req = Net::HTTP.start(DH_URI.host, DH_URI.port, OPENSSL_OPTIONS) do |http|
      http.get DH_URI
    end

    res = YAML.load(req.body)
    log.info "#{a[:cmd]}: #{res['result']}"

    [res['result'], res['data']]
  rescue Net::ReadTimeout
    log.warn "Dreamhost API timed out on #{a[:cmd]}"
  end
end
