require 'net/http'
require 'resolv'
require 'logger'
require 'yaml'
require 'configliere'

Settings.use :commandline, :config_file, :define

class NullLogger
  def debug(*) end
  def info(*)  end
  def warn(*)  end
  def error(*) end
  def fatal(*) end
end

class Reverie

  DH_URI = URI 'https://api.dreamhost.com/'
  IP_URI = URI 'http://myexternalip.com/raw'
  VERSION = '1.0.0'

  Settings.define :conf, type: :filename, description: 'The location of the configuration file',
                  default: Configliere::DEFAULT_CONFIG_LOCATION[:user].call('reverie')
  Settings.define :log,  type: :filename, description: 'The location of the log file'
  Settings.define :updated_at, type: DateTime

  attr_accessor :options, :args

  def self.update_dns
    Reverie.new.tap { |r| r.update_dns }
  end

  def initialize
    @options = Settings
    @options.resolve!
    @options.read @options.conf

    @log  = @options.log ? Logger.new(@options.log) : NullLogger.new

    @args = { key:    @options[:key],
              record: @options[:record],
              format: 'yaml' }

    @options.resolve!
  end

  def update_dns
    if Time.now - (@options[:updated_at] || Time.mktime(0)) > 900 and
       ip = get_ip and
       ip != @options[:ip] and
       replace_record @options[:record], ip
      @options.merge! ip: ip, updated_at: Time.now
      @options.save! @options.conf
      @log.info "#{ @options[:record] } updated to #{ ip }"
    else
      @log.debug "not updating #{ @options[:record] }"
    end
  end

  def replace_record(record, ip)
    return false unless record && ip

    status, res = api_call :list_records
    return false unless status == 'success'

    res.find { |r| r['record'] == record && r['editable'] == 1 }.tap { |r|
      api_call :remove_record, record: record, type: r['type'], value: r['value'] if r
    }

    status, res = api_call :add_record, record: record, type: 'A', value: ip, comment: 'Reverie'
    status == 'success'
  end

  def get_ip
    ip = Net::HTTP.get_response(IP_URI).body.chomp
    ip if ip =~ Resolv::IPv4::Regex
  rescue Net::ReadTimeout => e
    warn 'IP lookup timed out'
  end

private

  def api_call(cmd, args = {})
    a = @args.merge cmd: "dns-#{ cmd }", unique_id: SecureRandom.uuid
    a.merge! args

    DH_URI.query = URI.encode_www_form a
    @log.debug DH_URI.query

    opts = { use_ssl: true,
             ssl_version: :SSLv3,
             verify_mode: OpenSSL::SSL::VERIFY_PEER }
    res = YAML.load(Net::HTTP.start(DH_URI.host, DH_URI.port, opts) { |http| http.get DH_URI }.body)
    @log.debug "#{ a[:cmd] }: #{ res['result'] }"

    return res['result'], res['data']
  rescue Net::ReadTimeout
    @log.warn "Dreamhost API timed out on #{ a[:cmd] }"
  end

end
