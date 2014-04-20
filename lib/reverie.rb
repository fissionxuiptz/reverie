# Reverie

# Ported from Ian McKellar's dreamhost-ddns
# https://github.com/ianloic/dreamhost-ddns

require 'net/http'
require 'resolv'
require 'logger'
require 'yaml'
require 'configliere'
require 'reverie/version'

Settings.use :commandline, :config_file, :define

class Reverie
  DH_URI = URI 'https://api.dreamhost.com/'
  IP_URI = URI 'http://myexternalip.com/raw'

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
    time_out: '%s timed out on %s',
    kv:       '%s: %s'
  }

  Settings.define :conf,
                  type:        :filename,
                  description: 'The location of the configuration file',
                  default:     Configliere::DEFAULT_CONFIG_LOCATION[:user].call('reverie')

  Settings.define :log,
                  type:        :filename,
                  description: 'The location of the log file'

  def self.update_dns
    Reverie.new.tap { |r| r.update_dns }
  end

  def initialize
    Settings.resolve!
    Settings.read(@conf = Settings.delete('conf'))

    @log = Logger.new(Settings.log || STDOUT)
    @log.level = Settings.delete('debug') ? Logger::DEBUG : Logger::INFO
    Settings.delete('log') unless Settings.log

    @args = {
      key:    Settings[:key],
      record: Settings[:record],
      format: 'yaml'
    }
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
    ip = Net::HTTP.get_response(IP_URI).body.strip
    d :found, ip
    ip if ip =~ Resolv::IPv4::Regex
  rescue Net::ReadTimeout
    w :time_out, 'IP Lookup', IP_URI
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

    return res['result'], res['data']
  rescue Net::ReadTimeout
    w :time_out, 'Dreamhost API', a[:cmd]
  end

  def d(msg, *args)
    log :debug, msg, *args
  end

  def w(msg, *args)
    log :warn, msg, *args
  end

  def i(msg, *args)
    log :info, msg, *args
  end

  def log(level, msg, *args)
    @log.send level, MSGS[msg] ? MSGS[msg] % args : msg
  end
end
