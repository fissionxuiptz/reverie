require 'minitest/autorun'
require_relative '../lib/reverie'
require_relative '../lib/reverie/mojo'

r = Reverie.new

describe Reverie do
  describe 'reverie' do
    it 'loads mojo variation' do
      Reverie::SM_URI.to_s.must_equal 'http://softwaremojo.com/'
    end

    it 'inits a log' do
      r.instance_exec { @log.must_be_instance_of Logger }
    end

    it 'inits a conf' do
      r.instance_exec { @conf.must_equal ENV['HOME'] + '/.config/reverie/conf' }
    end

    it 'inits an args hash' do
      r.instance_exec do
        @args.must_be_instance_of Hash
        @args.keys.must_include :key
        @args.keys.must_include :record
        @args[:format].must_equal 'yaml'
      end
    end

    it 'gets an ip address' do
      r.get_ip.must_match Resolv::IPv4::Regex
    end
  end
end
