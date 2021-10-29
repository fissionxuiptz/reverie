# Reverie

# Ported from Ian McKellar's dreamhost-ddns
# https://github.com/ianloic/dreamhost-ddns

require "optparse"
require "pathname"
require_relative "reverie/version"
require_relative "reverie/base"

module Reverie
  module_function

  def update_dns
    Base.new.update_dns
  end
end
