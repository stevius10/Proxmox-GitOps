require 'json'

class Object
  def blank?; respond_to?(:empty?) ? empty? : !self; end
  def present?; !blank?; end
  def presence; blank? ? nil : self; end
  def presence_in(collection); return nil unless collection&.respond_to?(:include?); collection.include?(self) ? self : nil; end
  def try(method_name = nil, *args, &block)
    return nil if nil?; return instance_eval(&block) if block
    return nil unless (method_name || respond_to?(method_name, true))
    public_send(method_name, *args)
  end
end

class NilClass
  def blank?; true; end
  def present?; false; end
  def presence; nil; end
end

# Data types

class Hash
  def slice(*keys); keys.each_with_object({}) { |k,h| h[k] = self[k] if key?(k) }; end
  def except(*keys); dup.tap { |h| keys.each { |k| h.delete(k) } }; end
  def json(*a); JSON.generate(self, *a); end
end

class String
  def blank?; strip.empty? end
  def squish; strip.gsub(/\s+/, " ") end
  def mask; (length <= 4) ? '*' * length : "#{self[0]}#{self[1]}#{'*' * (length - 4)}#{self[-2]}#{self[-1]}" ; end
end

class Integer
  def minutes; self * 60; end
  def hours; self * 3600; end
end

# Extension

class Net::HTTPResponse
  def json(symbolize_names: false, allow_blank: false, validate_content_type: false)
    ct = self['content-type']
    return nil if validate_content_type && !(ct && ct.downcase.include?('application/json'))
    s = body.to_s
    return nil if allow_blank && s.strip.empty?
    JSON.parse(s, symbolize_names: symbolize_names)
  rescue => e
    self
  end

end