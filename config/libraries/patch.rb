require 'json'

class Object
  def blank?; respond_to?(:empty?) ? empty? : !self; end
  def present?; !blank?; end
  def logged; Logs.return("(logged) #{self.inspect}", self, level: :info); end
  def in(coll); coll&.respond_to?(:include?) ? (coll.include?(self) ? self : nil) : nil; end
  def or(default); self.to_s.presence || default.to_s; end
  def presence; blank? ? nil : self; end
  def try(m = nil, *a, &b)
    return nil if nil?; return instance_eval(&b) if b
    m && respond_to?(m, true) ? public_send(m, *a) : nil
  end
  def condition; case self
    when nil, false, 0, /\A(0|false|no|off)\z/i; false
    when true, 1, /\A(1|true|yes|on)\z/i; true
    else; !!self
  end end
end

class NilClass
  def blank?; true; end
  def present?; false; end
  def presence; nil; end
end

# Data types
class String
  def blank?; strip.empty? end
  def squish; strip.gsub(/\s+/, " ") end
  def mask; (length <= 4) ? '***': "#{self[0..1]}**#{self[-2..-1]}" ; end
end

class Integer
  def minutes; self * 60; end
  def hours; self * 3600; end
end

class Hash
  def slice(*k); k.each_with_object({}) { |key, h| h[key] = self[key] if key?(key) }; end
  def except(*k); dup.tap { |h| k.each { |key| h.delete(key) } }; end
  def json(*a); JSON.generate(self, *a); end
  def mask; JSON.generate(transform_values { |v| v.is_a?(String) ? v.mask : v.to_s }) end
end

class Array
  def mask; JSON.generate(map { |v| v.is_a?(String) ? v.mask : v.to_s }) end
end

# Extension

class Net::HTTPResponse
  def json(symbolize_names: false)
    body.to_s.strip.empty? ? nil : JSON.parse(body.to_s, symbolize_names: symbolize_names)
  rescue; self; end
end

# Reference

def include(rel)
  c = caller_locations(1, 1).first&.path
  p = File.expand_path(rel, c ? File.dirname(File.expand_path(c)) : Dir.pwd)
  File.exist?(p) ? instance_eval(File.read(p), p) : (Chef::Log.error("include not found: #{p}") && nil)
end

# Compatibility

unless defined?(Chef)
  module Chef; end
end
unless defined?(Chef::Log)
  module Chef
    module Log
      class << self
        def info(m)  $stdout.puts m end
        def warn(m)  $stderr.puts m end
        def error(m) $stderr.puts m end
        def debug(m) $stdout.puts m end
        def method_missing(k, *a) respond_to?(k) ? send(k, *a) : $stdout.puts(a.first) end
        def respond_to_missing?(*); true end
      end
    end
  end
end

