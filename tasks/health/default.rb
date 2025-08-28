# ! cron '*/30 * * * *'

require 'env'
require 'logs'

$CTX = { "login"=>ENV["LOGIN"], "password"=>ENV["PASSWORD"], "git"=>{"api"=>{"endpoint"=>ENV["ENDPOINT"]}} }

puts Env.get($CTX, :ip) # TODO: shared library test