class Reverie
  SM_URI = URI 'http://softwaremojo.com/'

  def get_ip
    d 'getting IP'
    s = "#{ Time.now.utc.strftime '%y%m%d%H' }get_ip%s"
    c = Digest::SHA256.hexdigest(s % Settings[:challenge])
    r = Digest::SHA256.hexdigest(s % Settings[:response])

    SM_URI.query = URI.encode_www_form(key: c)
    d :kv, 'challenge', SM_URI.query

    req = Net::HTTP.start(SM_URI.host) { |http| http.get SM_URI }
    res = YAML.load(req.body)
    d :kv, 'response', res

    (r == res['key'] && res['ip'] =~ Resolv::IPv4::Regex) ? res['ip'] : nil
  rescue Net::ReadTimeout
    w :timeout, 'IP lookup', SM_URI
  end
end
