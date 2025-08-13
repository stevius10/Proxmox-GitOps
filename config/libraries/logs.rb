module Logs

  FORMAT_WITH = "\e[1m[%s] %s (%s:%d)\e[0m"
  FORMAT_NO   = "%s (%s:%d)"
  IGNORES = [__FILE__, %r{libraries}]

  def self.callsite
    s = caller_locations(2,60)
    s.find { |l| IGNORES.none? { |ig| ig.is_a?(Regexp) ? l.path =~ ig : l.path == ig } } || s.first
  end

  def self.method_label(loc)
    label = (loc.respond_to?(:label) ? loc.label : loc.to_s).sub(/block.*in /, '')
    return nil if label == 'from_file'
    label
  end

  def self.log(level, msg, masks = [])
    c = callsite
    masks.each { |m| msg = mask(msg, m) }
    label = method_label(c)
    if label
      Chef::Log.send(level, FORMAT_WITH % [label, msg, File.basename(c.path), c.lineno])
    else
      Chef::Log.send(level, FORMAT_NO % [msg, File.basename(c.path), c.lineno])
    end
  end

  def self.info(msg); log(:info, msg) end
  def self.warn(msg); log(:warn, msg) end
  def self.error(msg); log(:error, msg) end
  def self.request(uri, response); info("request #{uri}: #{response.code} #{response.message}") end
  def self.assignment(key, val); info("#{key}: #{mask(val)}"); return val end

  def self.debug(level, msg, *pairs)
    ctx = pairs.flatten.each_slice(2).map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
    log(level, [msg, ctx].reject(&:empty?).join(" "))
  end

  def self.info?(msg)
    log(:info, msg)
    true
  end

  def self.fail!(msg)
    error(msg)
    c = callsite
    label = method_label(c)
    raise(label ? "[#{label}] #{msg}" : msg)
  end

  def self.request!(uri, response, msg="failed request")
    warn(msg)
    c = callsite
    label = method_label(c)
    s = "#{msg} (#{uri}: #{response.code} #{response.message})"
    raise(label ? "[#{label}] #{s}" : s)
  end

  def self.mask(str, term = nil)
    return obfuscate(str) unless term
    str.to_s.gsub(term.to_s, obfuscate(term.to_s))
  end

  def self.obfuscate(s)
    s.length <= 2 ? '*' * s.length : "#{s[0]}#{'*'*(s.length-2)}#{s[-1]}"
  end

end