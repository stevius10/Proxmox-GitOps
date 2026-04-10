module Logs
  F = "\e[1m[%s] %s (%s:%d)\e[0m"; NF = "%s (%s:%d)"

  def self.log(msg=nil, v: true, l: :info)
    c = (s = caller_locations(2, 60)).find { |i| [__FILE__, %r{libraries}].none? { |ig| ig.is_a?(Regexp) ? i.path =~ ig : i.path == ig } } || s.first
    m = (lb = (c.label || c.to_s).sub(/block.*in /, '')).eql?('from_file') ? nil : lb
    v ? Chef::Log.send(l, m ? F % [m, msg, File.basename(c.path), c.lineno] : NF % [msg, File.basename(c.path), c.lineno]) : (m ? "[#{m}]#{File.basename(c.path)}:#{c.lineno}" : "#{File.basename(c.path)}:#{c.lineno}")
  end

  def self.info(m); log(m) end; def self.warn(m); log(m, l: :warn) end
  def self.error(m, r: false); log(m, l: :error); raise m if r end
  def self.debug(*a, l: :debug); log("[(debug) #{a.reject(&:blank?).join(', ')}]", l: l) end
  def self.return(m, r, *a, l: :debug); debug("(return) #{m}: #{r}", *a, l: l); r end

  def self.try!(m, *a, r: false)
    return(m, yield, a)
  rescue Exception => e
    r ? raise("[#{log(v: false)}] #{m}: #{e.message}") : debug("(tried) #{m}: #{e.message}", *a)
  end

  def self.blank!(m, v); (v.nil? || (v.respond_to?(:empty?) && v.empty?)) ? error(m, r: true) : v end

  class << self
    { true: true, false: false, nil: nil }.each { |n, v| define_method(n) { |m| info(m); v } }
  end
end
