module Configliere
  DEFAULT_CONFIG_LOCATION[:user_config] = -> scope do
    Pathname(ENV['HOME'] || '/').join('.config').join(scope.to_s).join('conf')
  end
end
