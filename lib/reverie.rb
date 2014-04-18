require 'net/http'
require 'resolv'
require 'logger'
require 'yaml'
require 'configliere'

Settings.use :commandline, :config_file, :define

class Reverie

  DH_URI = URI 'https://api.dreamhost.com/'
  IP_URI = URI 'http://myexternalip.com/raw'
  VERSION = '1.0.1'

  Settings.define :conf, type: :filename, description: 'The location of the configuration file',
                  default: Configliere::DEFAULT_CONFIG_LOCATION[:user].call('reverie')
  Settings.define :log, type: :filename, description: 'The location of the log file'

  attr_accessor :options, :args

  def self.update_dns
    Reverie.new.tap { |r| r.update_dns }
  end

  def initialize
    @options = Settings
    @options.resolve!
    @options.read(@conf = @options.delete('conf'))

    @log = Logger.new(@options.log || STDOUT)
    @log.level = @options.delete('debug') ? Logger::DEBUG : Logger::INFO
    @options.delete('log') unless @options.log

    @args = { key:    @options[:key],
              record: @options[:record],
              format: 'yaml' }
  end

  def update_dns
    t = Time.now - (@options[:updated_at] || Time.mktime(0))
    return if
      (t < 900                               and @log.debug "too soon, updated #{ t.to_int }s ago") ||
      ((ip = get_ip).nil?                    and @log.debug 'get_ip failed') ||
      (ip == @options[:ip]                   and @log.debug "not updating #{ @options[:record ]}") ||
      (!replace_record @options[:record], ip and @log.debug 'replace_record failed')

    @options.merge! ip: ip, updated_at: Time.now
    @options.save! @conf
    @log.info "#{ @options[:record] } updated to #{ ip }"
  end

  def replace_record(record, ip)
    return false unless record && ip

    status, res = api_call :list_records
    return false unless status == 'success'

    res.detect { |r| r['record'] == record && r['editable'] == 1 }.tap { |r|
      api_call :remove_record, record: record, type: r['type'], value: r['value'] if r
    }

    status, res = api_call :add_record, record: record, type: 'A', value: ip, comment: "Reverie (#{ Time.now })"
    status == 'success'
  end

  def get_ip
    ip = Net::HTTP.get_response(IP_URI).body.chomp
    @log.debug "get_ip found #{ ip }"
    ip if ip =~ Resolv::IPv4::Regex
  rescue Net::ReadTimeout
    @log.warn 'IP lookup timed out'
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
