module Constants

  HEADER_JSON = {
    'Content-Type' => 'application/json',
    'Accept'       => 'application/json'
  }.freeze

  HEADER_FORM = {
    'Content-Type' => 'application/x-www-form-urlencoded'
  }.freeze

  URI_GITHUB_BASE = "https://api.github.com".freeze
  URI_GITHUB_LATEST = ->(owner, repo) { "#{URI_GITHUB_BASE}/repos/#{owner}/#{repo}/releases/latest" }
  URI_GITHUB_TAG = ->(owner, repo, tag) { tag.blank? ? nil : "#{URI_GITHUB_BASE}/repos/#{owner}/#{repo}/releases/tags/#{'v' unless tag.start_with?('v')}#{tag}" }

end
