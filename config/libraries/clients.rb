require_relative 'constants'
require_relative 'utils'

module Clients
  
  class Git

    def initialize(uri, username, password)
      @uri, @username, @password = uri, username, password
    end

    def get_repositories(owner=nil, repo=nil, body: nil, method: Net::HTTP::Get, target: nil)
      repositories = request(Constants::API_PATH_REPOSITORIES.call(@uri, owner, repo, target), body: body, method: method).json
      repositories.is_a?(Array) ? repositories : [repositories]
    end

    def auto_merge(owner=nil, repo=nil)
      get_repositories(owner, repo)
        .reject { |r|  [0, "0"].include?(r['open_pr_counter']) }
        .each   { |r|  get_repositories(owner, r['name'], target: "/pulls")
          .each { |rr| get_repositories(owner, r['name'], target: "/pulls/#{rr['number']}/merge", body: {"Do": "merge"}, method: Net::HTTP::Post) }
        }
    end

    def run_task(repo, owner: "tasks", ref: "main")
      get_repositories(owner, repo, target: "/actions/workflows").flat_map { |w| w['workflows'] }.each { |w|
        get_repositories(owner, repo, target: "/actions/workflows/#{w['id']}/dispatches", body: { ref: ref }, method: Net::HTTP::Post) }
    end

    private

    def request(uri, method: Net::HTTP::Get, body: nil)
      Utils.request(uri, method: method, body: body, headers: Constants::HEADER_JSON,
        user: @username, pass: @password, expect: false)
    end

  end

end
