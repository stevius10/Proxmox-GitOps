module Logs

  def self.log(msg, level: :info)
    c = callsite
    label = method_label(c)
    if label
      Chef::Log.send(level, FORMAT_WITH % [label, msg, File.basename(c.path), c.lineno])
    else
      Chef::Log.send(level, FORMAT_NO % [msg, File.basename(c.path), c.lineno])
    end
  end

  def self.info(msg); log(msg) end; def self.warn(msg); log(msg, level: :warn) end
  def self.error(msg, raise: true); log(msg, level: :error); raise msg if raise end
  def self.info?(msg, result: true); log(msg); result; end
  def self.request(uri, response); info("requested #{uri}: #{response&.code} #{response&.message}"); return response end
  def self.return(msg); log(msg.to_s); return msg end
  def self.returns(msg, result, level: :info); log(msg.to_s, level: level); return result end

  def self.debug(msg, *pairs, ctx: nil, level: :info)
    flat = pairs.flatten
    raise ArgumentError, "debug requires key value pairs (#{flat.length}: #{flat.inspect})" unless flat.length.even?
    input = flat.each_slice(2).to_h.transform_keys(&:to_s)
    payload = input.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
    log([msg, payload].reject { |s| s.blank? }.join(" "), level: level)

    if ctx
      node = Ctx.node(ctx)
      log("Context: { cookbook: #{node.cookbook_name}, recipe: #{node.recipe_name}, platform: #{node['platform']} }", level: :debug)
    end
  end

  def self.try!(msg, *pairs, ctx: nil, raise: false)
    return yield
  rescue => exception
    debug("failed: #{msg}: #{exception.message}", *(pairs.flatten), ctx: ctx, level: (raise ? :error : :warn))
    # debug(*(pairs.flatten), ctx: ctx, level: :debug)
    raise("[#{method_label(callsite)}] #{exception.message} #{msg}") if raise
  end

  def self.request!(uri, response, valid=[], msg: nil, ctx: nil)
    res = try!("failed request", [:uri, uri, :response, response]) do
      if valid.presence # if valid status code required
        raise("[#{method_label(callsite)}] #{msg}") unless
          (valid == true && (response.is_a?(Net::HTTPSuccess) or valid.include?(response.code.to_i)))
      end
      response ? "#{response.code} #{response.message}" : response
    end
    debug("[#{msg}] responded #{res}", [:uri, uri, :response, response], ctx: ctx)
    return response
  end

  # Helper

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

end
