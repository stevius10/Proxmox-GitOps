%w(. ../config ../../config).each do |dir| d = File.join(__dir__, dir, 'libraries')
  Dir[File.join(d, '**', '*.rb')].sort.each { |f| require f } if Dir.exist?(d)
end

ctx = { "host" => ENV["HOST"], "user_login" => ENV["USER_LOGIN"], "user_password" => ENV["USER_PASSWORD"] }
client = Clients::Git.new(Env.endpoint(ctx), ENV["USER_LOGIN"], ENV["USER_PASSWORD"])

client.auto_merge(Env.get(ctx, "AUTO_DEPLOY_STAGE").or("main"))

%w(update health).each do |task|
  client.run_task(task)
end unless Env.bootstrap?(ctx)
