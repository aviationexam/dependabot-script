# This script is designed to loop through all dependencies in a GHE, GitLab or
# Azure DevOps project, creating PRs where necessary.

require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/omnibus"
require "gitlab"
require "json"

credentials = [
  {
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ACCESS_TOKEN"] # A GitHub access token with read access to public repos
  }
]

# Full name of the repo you want to create pull requests for.
repo_name = ENV["PROJECT_PATH"] # namespace/project

# Directory where the base dependency files are.
directory = ENV["DIRECTORY_PATH"] || "/"

# Branch to look at. Defaults to repo's default branch
branch = ENV["BRANCH"]

# Name of the package manager you'd like to do the update for. Options are:
# - bundler
# - pip (includes pipenv)
# - npm_and_yarn
# - maven
# - gradle
# - cargo
# - hex
# - composer
# - nuget
# - dep
# - go_modules
# - elm
# - submodules
# - docker
# - terraform
package_manager = ENV["PACKAGE_MANAGER"] || "bundler"

# Expected to be a JSON object passed to the underlying components
options = JSON.parse(ENV["OPTIONS"] || "{}", {:symbolize_names => true})
puts "Running with options: #{options}"


provider_metadata = nil
if ENV["AZURE_WORK_ITEM"]
  azure_work_item = ENV["AZURE_WORK_ITEM"].to_i
  provider_metadata = {
    work_item: azure_work_item
  }
end

if ENV["ALTERNATIVE_NUGET_FEED"]
  alternative_token = nil
  unless ENV["ALTERNATIVE_NUGET_ACCESS_TOKEN"].nil?
    alternative_token = ":#{ENV["ALTERNATIVE_NUGET_ACCESS_TOKEN"]}"
  end

  credentials << {
    "type" => "nuget_feed",
    "url" => ENV["ALTERNATIVE_NUGET_FEED"],
    "token" => alternative_token
  }
end
if ENV["NUGET_ACCESS_TOKEN"] && ENV["NUGET_FEED"]
  credentials << {
    "type" => "nuget_feed",
    "url" => ENV["NUGET_FEED"],
    "token" => ":#{ENV["NUGET_ACCESS_TOKEN"]}" # Don't forget the colon
  }
end

if ENV["ALTERNATIVE_NPM_REGISTRY"]
  alternative_token = nil
  unless ENV["ALTERNATIVE_NPM_ACCESS_TOKEN"].nil?
    alternative_token = ":#{ENV["ALTERNATIVE_NPM_ACCESS_TOKEN"]}"
  end

  credentials << {
    "type" => "npm_registry",
    "registry" => ENV["ALTERNATIVE_NPM_REGISTRY"],
    "token" => alternative_token
  }
end
if ENV["NPM_ACCESS_TOKEN"] && ENV["NPM_REGISTRY"]
  credentials << {
    "type" => "npm_registry",
    "registry" => ENV["NPM_REGISTRY"],
    "token" => ":#{ENV["NPM_ACCESS_TOKEN"]}" # Don't forget the colon
  }
end

if ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"]
  credentials << {
    "type" => "git_source",
    "host" => ENV["GITHUB_ENTERPRISE_HOSTNAME"], # E.g., "ghe.mydomain.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"] # A GHE access token with API permission
  }

  source = Dependabot::Source.new(
    provider: "github",
    hostname: ENV["GITHUB_ENTERPRISE_HOSTNAME"],
    api_endpoint: "https://#{ENV['GITHUB_ENTERPRISE_HOSTNAME']}/api/v3/",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
elsif ENV["GITLAB_ACCESS_TOKEN"]
  gitlab_hostname = ENV["GITLAB_HOSTNAME"] || "gitlab.com"

  credentials << {
    "type" => "git_source",
    "host" => gitlab_hostname,
    "username" => "x-access-token",
    "password" => ENV["GITLAB_ACCESS_TOKEN"] # A GitLab access token with API permission
  }

  source = Dependabot::Source.new(
    provider: "gitlab",
    hostname: gitlab_hostname,
    api_endpoint: "https://#{gitlab_hostname}/api/v4",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
elsif ENV["AZURE_ACCESS_TOKEN"]
  azure_hostname = ENV["AZURE_HOSTNAME"] || "dev.azure.com"

  credentials << {
    "type" => "git_source",
    "host" => azure_hostname,
    "username" => "x-access-token",
    "password" => ENV["AZURE_ACCESS_TOKEN"]
  }

  source = Dependabot::Source.new(
    provider: "azure",
    hostname: azure_hostname,
    api_endpoint: "https://#{azure_hostname}/",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
elsif ENV["BITBUCKET_ACCESS_TOKEN"]
  bitbucket_hostname = ENV["BITBUCKET_HOSTNAME"] || "bitbucket.org"

  credentials << {
    "type" => "git_source",
    "host" => bitbucket_hostname,
    "username" => nil,
    "token" => ENV["BITBUCKET_ACCESS_TOKEN"]
  }

  source = Dependabot::Source.new(
    provider: "bitbucket",
    hostname: bitbucket_hostname,
    api_endpoint: ENV["BITBUCKET_API_URL"] || "https://api.bitbucket.org/2.0/",
    repo: repo_name,
    directory: directory,
    branch: nil,
  )
elsif ENV["BITBUCKET_APP_USERNAME"] && ENV["BITBUCKET_APP_PASSWORD"]
  bitbucket_hostname = ENV["BITBUCKET_HOSTNAME"] || "bitbucket.org"

  credentials << {
    "type" => "git_source",
    "host" => bitbucket_hostname,
    "username" => ENV["BITBUCKET_APP_USERNAME"],
    "password" => ENV["BITBUCKET_APP_PASSWORD"]
  }

  source = Dependabot::Source.new(
    provider: "bitbucket",
    hostname: bitbucket_hostname,
    api_endpoint: ENV["BITBUCKET_API_URL"] || "https://api.bitbucket.org/2.0/",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
else
  source = Dependabot::Source.new(
    provider: "github",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
end

##############################
# Fetch the dependency files #
##############################
puts "Fetching #{package_manager} dependency files for #{repo_name}"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  credentials: credentials,
  options: options,
)

files = fetcher.files
commit = fetcher.commit

##############################
# Parse the dependency files #
##############################
puts "Parsing dependencies information"
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  dependency_files: files,
  source: source,
  credentials: credentials,
  options: options,
)

dependencies = parser.parse

dependencies.select(&:top_level?).each do |dep|
  #########################################
  # Get update details for the dependency #
  #########################################
  checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
    dependency: dep,
    dependency_files: files,
    credentials: credentials,
    options: options,
  )

  if checker.up_to_date?
    puts "#{dep.name} (version #{dep.version}) - up to date"
  end

  next if checker.up_to_date?

  requirements_to_unlock =
    if !checker.requirements_unlocked_or_can_be?
      if checker.can_update?(requirements_to_unlock: :none) then :none
      else :update_not_possible
      end
    elsif checker.can_update?(requirements_to_unlock: :own) then :own
    elsif checker.can_update?(requirements_to_unlock: :all) then :all
    else :update_not_possible
    end

  next if requirements_to_unlock == :update_not_possible

  updated_deps = checker.updated_dependencies(
    requirements_to_unlock: requirements_to_unlock
  )

  #####################################
  # Generate updated dependency files #
  #####################################
  print "  - Updating #{dep.name} (from #{dep.version})…"
  updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
    dependencies: updated_deps,
    dependency_files: files,
    credentials: credentials,
    options: options,
  )

  updated_files = updater.updated_dependency_files

  ########################################
  # Create a pull request for the update #
  ########################################
  assignee = (ENV["PULL_REQUESTS_ASSIGNEE"] || ENV["GITLAB_ASSIGNEE_ID"])&.to_i
  assignees = assignee ? [assignee] : assignee
  pr_creator = Dependabot::PullRequestCreator.new(
    source: source,
    base_commit: commit,
    dependencies: updated_deps,
    files: updated_files,
    credentials: credentials,
    assignees: assignees,
    author_details: { name: "Dependabot", email: "no-reply@github.com" },
    label_language: true,
    provider_metadata: provider_metadata
  )
  pull_request = pr_creator.create
  puts " submitted"

  next unless pull_request

  # Enable GitLab "merge when pipeline succeeds" feature.
  # Merge requests created and successfully tested will be merge automatically.
  if ENV["GITLAB_AUTO_MERGE"]
    g = Gitlab.client(
      endpoint: source.api_endpoint,
      private_token: ENV["GITLAB_ACCESS_TOKEN"]
    )
    g.accept_merge_request(
      source.repo,
      pull_request.iid,
      merge_when_pipeline_succeeds: true,
      should_remove_source_branch: true
    )
  elsif ENV["AZURE_AUTO_MERGE"] && ENV["AZURE_REVIEWER"]
    azure_reviewer = ENV["AZURE_REVIEWER"]

    azure_client = Azure.client(
      endpoint: source.api_endpoint,
      private_token: ENV["AZURE_ACCESS_TOKEN"]
    )

    content = {
      autoCompleteSetBy: {
        id: "#{azure_reviewer}"
      },
      completionOptions: {
        mergeCommitMessage: "Localization update",
        deleteSourceBranch: true,
        squashMerge: true,
        mergeStrategy: "squash",
        transitionWorkItems: false,
        autoCompleteIgnoreConfigIds: []
      }
    }
    auto_merge_url = "https://dev.azure.com/aviationexam/#{source.project}/_apis/git/repositories/#{source.unscoped_repo}/pullrequests/#{pull_request.pullRequestId}?api-version=6.0"

    url = auto_merge_url
    json = content.to_json
    response = Excon.patch(
      url,
      body: json,
      user: azure_client.credentials&.fetch("username", nil),
      password: azure_client.credentials&.fetch("password", nil),
      idempotent: true,
      **SharedHelpers.excon_defaults(
        headers: auth_header.merge(
          {
            "Content-Type" => "application/json"
          }
        )
      )
    )

    raise InternalServerError if response.status == 500
    raise BadGateway if response.status == 502
    raise ServiceNotAvailable if response.status == 503
  end
end

puts "Done"
