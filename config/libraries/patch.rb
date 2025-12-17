require 'json'

class Object
  def blank?; respond_to?(:empty?) ? empty? : !self; end
  def present?; !blank?; end
  def logged; Logs.return("(logged) #{self.inspect}", self, level: :info); end
  def in(collection); return nil unless collection&.respond_to?(:include?); collection.include?(self) ? self : nil; end
  def or(default); self.to_s.presence || default.to_s; end
  def presence; blank? ? nil : self; end
  def try(method_name = nil, *args, &block)
    return nil if nil?; return instance_eval(&block) if block
    return nil unless method_name && respond_to?(method_name, true)
    public_send(method_name, *args)
  end
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
  def mask; (length <= 4) ? '***': "#{self[0]}#{self[1]}#{'**'}#{self[-2]}#{self[-1]}" ; end
end

class Integer
  def minutes; self * 60; end
  def hours; self * 3600; end
end

class Hash
  def slice(*keys); keys.each_with_object({}) { |k,h| h[k] = self[k] if key?(k) }; end
  def except(*keys); dup.tap { |h| keys.each { |k| h.delete(k) } }; end
  def json(*a); JSON.generate(self, *a); end
  def mask; JSON.generate(transform_values { |v| v.is_a?(String) ? v.mask : v.to_s }) end
end

class Array
  def mask; JSON.generate(map { |v| v.is_a?(String) ? v.mask : v.to_s }) end
end

# Extension

class Net::HTTPResponse
  def json(symbolize_names: false, allow_blank: false, validate_content_type: false)
    ct = self['content-type']
    return nil if validate_content_type && !(ct && ct.downcase.include?('application/json'))
    s = body.to_s
    return nil if allow_blank && s.strip.empty?
    JSON.parse(s, symbolize_names: symbolize_names)
  rescue
    self
  end
end

# Reference

def include(rel)
  caller_location = caller_locations(1,1)&.first
  instance_eval(::File.read(path = ::File.expand_path(::File.join(caller_location&.path ?
    ::File.dirname(::File.expand_path(caller_location.path)) : ::Dir.pwd, rel))), path)
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
