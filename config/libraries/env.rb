require 'net/http'
require 'uri'
require 'json'
require 'active_support/core_ext/object/blank'

module Env

  def self.creds(node, var_name_login="login", var_name_password="password")
    [ENV[var_name_login.to_s.upcase] || node.dig(var_name_login.to_sym), ENV[var_name_password.to_s.upcase] ||  node.dig(var_name_password.to_sym)]
  end

  def self.get(node, key)
    node[key].to_s.presence || ENV[key.to_s.upcase].presence || get_variable(node, key) || Chef::Log.warn("Failed: Get '#{key}'")
  end

  def self.get_variable(node, key)
    response = request(node, key)
    raise "Failed: Get '#{key}': #{response.code}" unless response.is_a?(Net::HTTPOK)
    JSON.parse(response.body).dig('data', 'value')
  end

  def self.set_variable(node, key, value)
    response = request(node, key, { name: key, value: value.to_s }.to_json)
    raise "Failed: Set '#{key}': #{response.code}" unless %w[201 204 409 422].include?(response.code)
    true
  end

  class << self
    alias_method :set, :set_variable
  end

  private_class_method def self.request(node, key, value = nil)
    (request = (value ? Net::HTTP::Post : Net::HTTP::Get).new(URI.parse("http://#{get(node, 'host')}:8080/api/v1/orgs/srv/actions/variables/#{key}"))).basic_auth(*creds(node))
    (request.content_type = 'application/json' and request.body = value) if value
    Net::HTTP.new(request.uri.host, request.uri.port).request(request)
  end

end
