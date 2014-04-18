Reverie.class_eval do
  SM_URI = URI 'http://softwaremojo.com/'

  def get_ip
    @log.debug "getting IP"
    t = Time.now.utc
    c = Digest::SHA256.hexdigest "#{ t.strftime('%y%m%d%H') }get_ip#{ @options[:challenge] }"
    r = Digest::SHA256.hexdigest "#{ t.strftime('%y%m%d%H') }get_ip#{ @options[:response] }"

    SM_URI.query = URI.encode_www_form key: c
    @log.debug "challenge: #{ SM_URI.query }"

    res = YAML.load(Net::HTTP.start(SM_URI.host) { |http| http.get SM_URI }.body)
    @log.debug "response: #{ res }"

    (r == res['key'] and res['ip'] =~ Resolv::IPv4::Regex) ? res['ip'] : nil
  rescue Net::ReadTimeout
    @log.warn 'IP lookup timed out'
  end
end
