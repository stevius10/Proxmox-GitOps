%w(. ../config ../../config).each do |dir| d = File.join(__dir__, dir, 'libraries')
  Dir[File.join(d, '**', '*.rb')].sort.each { |f| require f } if Dir.exist?(d)
end
ctx = { "host" => ENV["HOST"], "login" => ENV["LOGIN"], "password" => ENV["PASSWORD"] }

Clients::Git.new(Env.endpoint(ctx), ENV["LOGIN"], ENV["PASSWORD"]).auto_pulls("main", "config")
