require_relative 'utils'

module Clients
  
  class Git

    def initialize(uri, username, password)
      @uri, @username, @password = uri, username, password
    end

    def auto_pulls(owner=nil, repo=nil)
      get_repositories(owner, repo)
        .reject { |r| [0, "0"].include?(r['open_pr_counter']) }
        .each   { |r| get_repositories(owner, r['name'], target: "/pulls")
          .each   { |sub_r| get_repositories(owner, r['name'], target: "/pulls/#{sub_r['number']}/merge", method: Net::HTTP::Post) }
        }
    end

    private

    def get_repositories(owner=nil, repo=nil, method: Net::HTTP::Get, target: nil)
      repositories = JSON.parse(request(Constants::API_PATH_REPOSITORIES.call(@uri, owner, repo, target), method: method).body)
      repositories.is_a?(Array) ? repositories : [repositories]
    end

    def request(uri, method: Net::HTTP::Get, body: nil)
      Utils.request(uri, method: method, body: body, headers: Constants::HEADER_JSON,
        user: @username, pass: @password, expect: false)
    end

  end

end
