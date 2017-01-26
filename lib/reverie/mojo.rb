require 'mojo/multi_delegator'

class Reverie
  SM_URI = URI 'http://softwaremojo.com/'

  def init_log
    log_level = Settings.delete('debug') ? Logger::DEBUG : Logger::INFO

    @log = if log_level == 0 && Settings.log
      Logger.new(MultiDelegator.delegate(:write, :close).to(File.open(Settings.log, 'a'), STDOUT))
    else
      Logger.new(Settings.log || STDOUT)
    end

    @log.level = log_level
    Settings.delete('log') unless Settings.log
  end

  def get_ip
    uri = SM_URI.dup

    log.info "connecting to #{uri}"
    s = "#{ Time.now.utc.strftime '%y%m%d%H' }get_ip%s"
    c = Digest::SHA256.hexdigest(s % Settings[:challenge])
    r = Digest::SHA256.hexdigest(s % Settings[:response])

    uri.query = URI.encode_www_form(key: c)
    log.info "challenge: #{uri.query}"

    req = Net::HTTP.start(uri.host) { |http| http.get uri }
    res = YAML.load(req.body)
    log.info "response: #{res}"

    (r == res['key'] && res['ip'] =~ Resolv::IPv4::Regex) ? res['ip'] : nil
  rescue Net::ReadTimeout
    log.warn "IP Lookup timed out on #{uri}"
  end
end
