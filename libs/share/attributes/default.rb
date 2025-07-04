include_attribute 'config::default'

default['mount'] = ENV['MOUNT'].to_s.split(',').each_with_object({}) do |entry, hash|
  name, size = entry.split(':')
  hash[name.strip] = {
    'path' => name == 'share' ? '/share' : "/share/#{name}",
    'size' => size.to_i
  }
end