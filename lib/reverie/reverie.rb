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

  OPENSSL_V3 = {
    use_ssl:     true,
    ssl_version: :SSLv3,
    verify_mode: OpenSSL::SSL::VERIFY_PEER
  }

  MSGS = {
    success:  '%s updated to %s',
    fail:     '%s failed',
    found:    'get_ip found %s',
    too_soon: 'too soon, updated %ds ago',
    same:     'not updating %s',
    timeout:  '%s timed out on %s',
    kv:       '%s: %s',
    start:    'connecting to %s'
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
    Settings.read @conf
  end

  def init_log
    @log = Logger.new(Settings.log || STDOUT)
    @log.level = Settings.delete('debug') ? Logger::DEBUG : Logger::INFO
    Settings.delete('log') unless Settings.log
  end

  def settings
    Settings
  end

  def update_dns
    t = Time.now - (Settings[:updated_at] || Time.mktime(0))

    if (t < 900             and d :too_soon, t) ||
       ((ip = get_ip).nil?  and d :fail, 'get_ip') ||
       (ip == Settings[:ip] and d :same, Settings[:record]) ||
       (!replace_record Settings[:record], ip and d :fail, 'replace_record')
      return
    end

    Settings.merge! ip: ip, updated_at: Time.now
    Settings.save! @conf
    i :success, Settings[:record], ip
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
    d :start, IP_URI
    ip = Net::HTTP.get_response(IP_URI).body.strip
    d :found, ip
    ip if ip =~ Resolv::IPv4::Regex
  rescue Net::ReadTimeout
    w :timeout, 'IP Lookup', IP_URI
  end

  private

  def api_call(cmd, args = {})
    a = @args.merge(cmd: "dns-#{ cmd }", unique_id: SecureRandom.uuid)
    a.merge! args

    d(DH_URI.query = URI.encode_www_form(a))

    req = Net::HTTP.start(DH_URI.host, DH_URI.port, OPENSSL_V3) do |http|
      http.get DH_URI
    end

    res = YAML.load(req.body)
    d :kv, a[:cmd], res['result']

    [res['result'], res['data']]
  rescue Net::ReadTimeout
    w :timeout, 'Dreamhost API', a[:cmd]
  end

  def d(msg, *args)
    __log :debug, msg, *args
  end

  def w(msg, *args)
    __log :warn, msg, *args
  end

  def i(msg, *args)
    __log :info, msg, *args
  end

  def __log(level, msg, *args)
    @log.send level, MSGS[msg] ? MSGS[msg] % args : msg
  end
end
