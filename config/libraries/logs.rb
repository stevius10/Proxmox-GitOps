module Logs

  FORMAT="\e[1m[%s] %s (%s:%d)\e[0m"; NO_FORMAT="%s (%s:%d)"

  def self.log(msg=nil, verbose: true, level: :info)
    (c = (s = caller_locations(2, 60)).find { |l| [__FILE__, %r{libraries}].none? { |ig| ig.is_a?(Regexp) ? l.path =~ ig : l.path == ig } } || s.first); f = File.basename(c.path); l = c.lineno
    m = ((label = (c.respond_to?(:label) ? c.label : c.to_s).sub(/block.*in /, '')).eql?('from_file') ? nil : label)
    verbose ? Chef::Log.send(level, m ? FORMAT % [m, msg, f, l] : NO_FORMAT % [msg, f, l]) : (m ? "[#{m}]#{f}:#{l}" : "#{f}:#{l}")
  end

  def self.info(msg); log(msg) end; def self.warn(msg); log(msg, level: :warn) end
  def self.error(msg, raise: false); log(msg, level: :error); raise msg if raise end

  def self.debug(*args, level: :debug)
    message = args.reject(&:blank?).join(", ")
    log("[(debug) #{message}]", level: level)
  end

  def self.return(msg, result, *args, level: :info)
    message = "(return) #{msg}: #{result}"
    args.blank? ? log(message, level: level) : debug(message, *args, level: level)
    return result
  end

  def self.try!(msg, *args, raise: false)
    Logs.return("(try) #{msg}", yield, args, level: :info)
  rescue Exception => e
    raise ? raise("[#{log(verbose: false)}] #{msg}: #{e.message}") : debug("(tried) #{msg}: #{e.message}", *args)
  end

  def self.blank!(msg, value); error(msg, raise: true) if value.nil? || (value.respond_to?(:empty?) && value.empty?); value; end

  class << self
    %i[true false nil].each do |result|
      define_method(result) do |msg|
        self.info(msg); return result
      end
    end
  end
end
