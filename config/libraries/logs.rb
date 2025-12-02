module Logs

  FORMAT="\e[1m[%s] %s (%s:%d)\e[0m"; NO_FORMAT="%s (%s:%d)"

  def self.log(msg=nil, verbose: true, level: :info)
    (c = (s = caller_locations(2, 60)).find { |l| [__FILE__, %r{libraries}].none? { |ig| ig.is_a?(Regexp) ? l.path =~ ig : l.path == ig } } || s.first); f = File.basename(c.path); l = c.lineno
    m = ((label = (c.respond_to?(:label) ? c.label : c.to_s).sub(/block.*in /, '')).eql?('from_file') ? nil : label)
    verbose ? Chef::Log.send(level, m ? FORMAT % [m, msg, f, l] : NO_FORMAT % [msg, f, l]) : (m ? "[#{m}]#{f}:#{l}" : "#{f}:#{l}")
  end

  def self.info(msg); log(msg) end; def self.warn(msg); log(msg, level: :warn) end
  def self.error(msg, fail: false); log(msg, level: :error); raise msg if fail end
  def self.error!(msg); error(msg, fail: true) end
  def self.info?(msg, result: true); log(msg); result; end
  def self.request(uri, response); debug("#{response&.code} #{response&.message} (#{uri})"); return response end
  def self.return(msg); log(msg); return msg end
  def self.returns(msg, result, level: :info); log("#{msg}: #{result}", level: level); return result end

  def self.debug(msg, *pairs, level: :info)
    flat = pairs.flatten; raise ArgumentError, "(#{flat.length}: #{flat.inspect})" unless flat.length.even?
    log([msg, ((flat.each_slice(2).to_h.transform_keys(&:to_s)).map { |k, v| "#{k}=#{v.inspect}" }.join(" "))].reject(&:blank?).join(" "), level: level)
  end

  def self.try!(msg, *pairs, fail: false)
    result = yield; Logs.returns(["(try: #{msg})", result].join(" "), result, level: :debug)
  rescue => exception
    fail ? raise("[#{log(verbose: false)}] #{msg}: #{exception.message}") : debug("(try) #{msg}: #{exception.message}", pairs: pairs)
  end

  def self.request!(uri, response, valid=[], msg: nil)
    raise("[#{log(verbose: false)}] #{msg}") unless valid.blank? || ([true, false].include?(valid) ? response.is_a?(Net::HTTPSuccess) : valid.include?(response.code.to_i))
    returns("#{msg}: #{response&.code} #{response&.message} (#{uri})", response)
  end

  def self.blank!(msg, value); error!(msg) if value.nil? || (value.respond_to?(:empty?) && value.empty?); value; end

end