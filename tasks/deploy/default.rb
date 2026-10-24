%w(. ../config ../../config).each do |dir| d = File.join(__dir__, dir, 'libraries')
  Dir[File.join(d, '**', '*.rb')].sort.each { |f| require f } if Dir.exist?(d)
end

Clients::Git.new(Env.endpoint( {"host"=>ENV["HOST"]} ), ENV["LOGIN"], ENV["PASSWORD"]).auto_merge(owner="main")

%w(update health).each do |task|
  Clients::Git.new(Env.endpoint( {"host"=>ENV["HOST"]} ), ENV["LOGIN"], ENV["PASSWORD"]).run_task(task)
end
