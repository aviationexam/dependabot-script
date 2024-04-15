# This script is designed to loop through all dependencies in a GHE, GitLab or
# Azure DevOps project, creating PRs where necessary.

require "./custom_dependency_group_strategy.rb"
require "./custom_gradle_update_checker.rb"
require "./max_version_nuget_project_file_parser.rb"
require "./custom_nuget_file_parser.rb"
require "./custom_nuget_update_checker.rb"
require "./custom_nuget_file_updater.rb"
require "dependabot/credential"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/omnibus"
require "dependabot/clients/azure"
require "gitlab"
require "json"

$stdout.sync = true

credentials = [
  Dependabot::Credential.new(
    {
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => ENV["GITHUB_ACCESS_TOKEN"] # A GitHub access token with read access to public repos
    }
  )
]

# Full name of the repo you want to create pull requests for.
repo_name = ENV["PROJECT_PATH"] # namespace/project
submodule_repo_name = ENV["SUBMODULE_PROJECT_PATH"] # namespace/project

# Directory where the base dependency files are.
directory = ENV["DIRECTORY_PATH"] || "/"
submodule_directory = ENV["SUBMODULE_DIRECTORY_PATH"] || "/"

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

Dependabot.logger = Logger.new($stdout, level: Logger::INFO)

# Expected to be a JSON object passed to the underlying components
options = JSON.parse(ENV["OPTIONS"] || "{}", { :symbolize_names => true })
Dependabot.logger.info("Running with options: #{options}")

provider_metadata = nil
if ENV["AZURE_WORK_ITEM"]
  azure_work_item = ENV["AZURE_WORK_ITEM"].to_i
  provider_metadata = {
    work_item: azure_work_item
  }
end

ignore_dependency = []
if ENV["IGNORE_DEPENDENCY"]
  ignore_dependency = ENV["IGNORE_DEPENDENCY"].split(",")
end

ignore_directory = []
if ENV["IGNORE_DIRECTORY"]
  ignore_directory = ENV["IGNORE_DIRECTORY"].split(";")
end

if ENV["ALTERNATIVE_NUGET_FEED"]
  alternative_token = nil
  unless ENV["ALTERNATIVE_NUGET_ACCESS_TOKEN"].nil?
    alternative_token = ":#{ENV["ALTERNATIVE_NUGET_ACCESS_TOKEN"]}"
  end

  credentials << Dependabot::Credential.new({
    "type" => "nuget_feed",
    "url" => ENV["ALTERNATIVE_NUGET_FEED"],
    "token" => alternative_token
  })
end
if ENV["NUGET_ACCESS_TOKEN"] && ENV["NUGET_FEED"]
  credentials << Dependabot::Credential.new({
    "type" => "nuget_feed",
    "url" => ENV["NUGET_FEED"],
    "token" => ":#{ENV["NUGET_ACCESS_TOKEN"]}" # Don't forget the colon
  })
end

if ENV["PACKAGE_MANAGER"] == "gradle"
  credentials << Dependabot::Credential.new({
    "type" => "maven_repository",
    "url" => "https://repo1.maven.org/maven2/",
  })
end

if ENV["GRADLE_ACCESS_TOKEN"] && ENV["GRADLE_FEED"]
  credentials << Dependabot::Credential.new({
    "type" => "maven_repository",
    "url" => ENV["GRADLE_FEED"],
    "username" => "aviationexam",
    "password" => "#{ENV["GRADLE_ACCESS_TOKEN"]}"
  })
end

if ENV["NPM_ACCESS_TOKEN"] && ENV["NPM_REGISTRY"]
  credentials << Dependabot::Credential.new({
    "type" => "npm_registry",
    "registry" => ENV["NPM_REGISTRY"],
    "url" => ENV["NPM_REGISTRY_URL"],
    "token" => ":#{ENV["NPM_ACCESS_TOKEN"]}" # Don't forget the colon
  })
end
if ENV["ALTERNATIVE_NPM_REGISTRY"]
  alternative_token = nil
  unless ENV["ALTERNATIVE_NPM_ACCESS_TOKEN"].nil?
    alternative_token = ":#{ENV["ALTERNATIVE_NPM_ACCESS_TOKEN"]}"
  end

  credentials << Dependabot::Credential.new({
    "type" => "npm_registry",
    "registry" => ENV["ALTERNATIVE_NPM_REGISTRY"],
    "url" => ENV["ALTERNATIVE_NPM_REGISTRY_URL"],
    "token" => alternative_token
  })
end

if ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"]
  credentials << Dependabot::Credential.new({
    "type" => "git_source",
    "host" => ENV["GITHUB_ENTERPRISE_HOSTNAME"], # E.g., "ghe.mydomain.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"] # A GHE access token with API permission
  })

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

  credentials << Dependabot::Credential.new({
    "type" => "git_source",
    "host" => gitlab_hostname,
    "username" => "x-access-token",
    "password" => ENV["GITLAB_ACCESS_TOKEN"] # A GitLab access token with API permission
  })

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

  credentials << Dependabot::Credential.new({
    "type" => "git_source",
    "host" => azure_hostname,
    "username" => "x-access-token",
    "password" => ENV["AZURE_ACCESS_TOKEN"]
  })

  source = Dependabot::Source.new(
    provider: "azure",
    hostname: azure_hostname,
    api_endpoint: "https://#{azure_hostname}/",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )

  submodule_source = submodule_repo_name != nil && submodule_directory != nil ? Dependabot::Source.new(
    provider: "azure",
    hostname: azure_hostname,
    api_endpoint: "https://#{azure_hostname}/",
    repo: submodule_repo_name,
    directory: submodule_directory,
    branch: branch,
  ) : nil
elsif ENV["BITBUCKET_ACCESS_TOKEN"]
  bitbucket_hostname = ENV["BITBUCKET_HOSTNAME"] || "bitbucket.org"

  credentials << Dependabot::Credential.new({
    "type" => "git_source",
    "host" => bitbucket_hostname,
    "username" => nil,
    "token" => ENV["BITBUCKET_ACCESS_TOKEN"]
  })

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

  credentials << Dependabot::Credential.new({
    "type" => "git_source",
    "host" => bitbucket_hostname,
    "username" => ENV["BITBUCKET_APP_USERNAME"],
    "password" => ENV["BITBUCKET_APP_PASSWORD"]
  })

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

ignore_dependency.each do |d|
  Dependabot.logger.info("Ignored dependency: #{d}")
end

always_clone = true
vendor_dependencies = options[:vendor_dependencies]
repo_contents_path = File.expand_path(File.join("tmp", repo_name.split("/"))) if vendor_dependencies || always_clone
submodule_repo_contents_path = File.expand_path(File.join("tmp", submodule_repo_name.split("/"))) if submodule_repo_name != nil && (vendor_dependencies || always_clone)

##############################
# Fetch the dependency files #
##############################
Dependabot.logger.info("Fetching #{package_manager} dependency files for #{repo_name}")
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  credentials: credentials,
  repo_contents_path: repo_contents_path,
  options: options,
)
submodule_fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: submodule_source,
  credentials: credentials,
  repo_contents_path: submodule_repo_contents_path,
  options: options,
) if submodule_source

files = fetcher.files
commit = fetcher.commit

submodule_files = submodule_fetcher.files if submodule_fetcher

ignore_directory.each do |d|
  Dependabot.logger.info("Ignored directory: #{d}")

  ignored_source = files.select { |file| file.name.include? d }

  files = files.reject { |file| file.name.include? d }

  ignored_source.each do |i|
    Dependabot.logger.info(" - ignored source: #{i}")
  end
end

max_version_nuget_project_file_parser = Dependabot::Nuget::MaxVersionNugetProjectFileParser.new(
  dependency_files: files,
)
max_version_nuget_project_file_parser_submodule_files = Dependabot::Nuget::MaxVersionNugetProjectFileParser.new(
  dependency_files: submodule_files,
) if submodule_files

options[:package_max_versions] = max_version_nuget_project_file_parser.package_max_versions

if max_version_nuget_project_file_parser_submodule_files != nil
  max_version_nuget_project_file_parser_submodule_files.package_max_versions.each do |package, version|
    options[:package_max_versions][package] = version
  end
end

##############################
# Parse the dependency files #
##############################
Dependabot.logger.info("Parsing dependencies information")
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  dependency_files: files,
  repo_contents_path: repo_contents_path,
  source: source,
  credentials: credentials,
  options: options,
)

dependencies = parser.parse

if options[:package_max_versions]&.any?
  dependencies = dependencies.select { |dep|
    is_in_csproj = dep.requirements.any? { |requirement|
      requirement[:file].end_with?(".csproj")
    }

    is_in_props = dep.requirements.any? { |requirement|
      requirement[:file].end_with?(".props")
    }

    is_in_csproj ? is_in_props : true
  }
end

# dependencies = dependencies.select { |dep| dep.name == "Sentry.AspNetCore" }

def auth_header_for(token)
  return {} unless token

  if token.include?(":")
    encoded_token = Base64.encode64(token).delete("\n")
    { "Authorization" => "Basic #{encoded_token}" }
  elsif Base64.decode64(token).ascii_only? &&
    Base64.decode64(token).include?(":")
    { "Authorization" => "Basic #{token.delete("\n")}" }
  else
    { "Authorization" => "Bearer #{token}" }
  end
end

def get_package_prefix(dependency)
  if dependency.name.include? '.'
    dependency.name.split('.').first
  elsif dependency.name.include? '/'
    dependency.name.split('/').first
  else
    dependency.name
  end
end

def longest_common_substr(strings)
  shortest = strings.min_by &:length
  maxlen = shortest.length
  maxlen.downto(0) do |len|
    0.upto(maxlen - len) do |start|
      substr = shortest[start,len]
      return substr if strings.all?{|str| str.include? substr }
    end
  end
end

dependencies_to_update =
  dependencies
    .select(&:top_level?)
    .sort_by { |dep| dep.name }
    .reject { |dep|
      if dep.version == nil
        Dependabot.logger.info("__ #{dep.name} - managed in submodule")

        true
      elsif dep.version.start_with?('$')
        Dependabot.logger.info("__ #{dep.name} - managed externally")

        true
      else
        false
      end
    }
    #########################################
    # Get update details for the dependency #
    #########################################
    .map { |dep| Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
      dependency: dep,
      dependency_files: files,
      credentials: credentials,
      repo_contents_path: repo_contents_path,
      options: options,
    ) }
    .reject { |checker|
      dep = checker.dependency
      if checker.up_to_date?
        Dependabot.logger.info("#{dep.name} (version #{dep.version}) - up to date")
      end

      if not checker.up_to_date? and ignore_dependency.include? dep.name
        Dependabot.logger.info("__ #{dep.name} (version #{dep.version}) - ignoring")
      end

      (checker.up_to_date? or ignore_dependency.include? dep.name)
    }
    .map { |checker|
      requirements_to_unlock =
        if !checker.requirements_unlocked_or_can_be?
          #noinspection RubyThenInMultilineConditionalInspection
          if checker.can_update?(requirements_to_unlock: :none) then :none
          else :update_not_possible
          end
        elsif checker.can_update?(requirements_to_unlock: :own) then :own
        elsif checker.can_update?(requirements_to_unlock: :all) then :all
        else :update_not_possible
        end

      {
        checker: checker,
        requirements_to_unlock: requirements_to_unlock,
      }
    }
    .reject { |item| item[:requirements_to_unlock] == :update_not_possible }
    .map { |item|
      updated_deps = item[:checker].updated_dependencies(
        requirements_to_unlock: item[:requirements_to_unlock]
      )
      name = item[:checker].dependency.name
      primary_dep = updated_deps.reject { |d| d.name != name }.first

      {
        checker: item[:checker],
        updated_deps: updated_deps,
        primary_dep: primary_dep,
        version_postfix: "#{primary_dep.version}/#{primary_dep.previous_version}"
      }
    }
    .group_by { |item|
      dep = item[:primary_dep]
      version_postfix = item[:version_postfix]

      "#{get_package_prefix(dep)}/#{version_postfix}"
    }

dependencies_to_update.each do |key, items|
  updated_deps = items.map { |item| item[:updated_deps] }.flatten

  if updated_deps.length > 1
    updated_dep_names = items.map { |item| item[:primary_dep].name }.flatten
    version_postfix = items.map { |item| item[:version_postfix] }.first
    lcs = longest_common_substr(updated_dep_names).chomp('.')

    rules = Hash.new
    rules[key] = ["#{key}*"]
    dependency_group = Dependabot::DependencyGroup.new(name: "#{lcs}/#{version_postfix}", rules: rules)
  else
    dependency_group = nil
  end

  #####################################
  # Generate updated dependency files #
  #####################################
  updated_deps.each do |d|
    Dependabot.logger.info("  - Updating #{d.name} (from #{d.previous_version} to #{d.version})…")
  end

  updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
    dependencies: updated_deps,
    dependency_files: files,
    repo_contents_path: repo_contents_path,
    credentials: credentials,
    options: options,
  )

  updated_files = updater.updated_dependency_files.uniq { |updated_file| updated_file.path }

  next unless updated_files.any?

  ########################################
  # Create a pull request for the update #
  ########################################
  assignees = []
  reviewers = []

  if ENV["PULL_REQUESTS_ASSIGNEE"]
    assignees = ENV["PULL_REQUESTS_ASSIGNEE"].split(",")
  elsif ENV["GITLAB_ASSIGNEE_ID"]
    assignees = ENV["GITLAB_ASSIGNEE_ID"].split(",").map(&:to_i)
  end

  pr_creator = Dependabot::PullRequestCreator.new(
    source: source,
    base_commit: commit,
    dependencies: updated_deps,
    dependency_group: dependency_group,
    files: updated_files,
    credentials: credentials,
    reviewers: reviewers,
    assignees: assignees,
    author_details: { name: "Dependabot", email: "no-reply@github.com" },
    label_language: true,
    provider_metadata: provider_metadata
  )

  if dependency_group != nil
    branch_namer = pr_creator.send(:branch_namer)
    pr_creator_branch_namer_strategy = branch_namer.send(:strategy)

    branch_name_strategy = Dependabot::PullRequestCreator::BranchNamer::CustomDependencyGroupStrategy.new(
      dependencies: pr_creator_branch_namer_strategy.dependencies,
      files: pr_creator_branch_namer_strategy.files,
      target_branch: pr_creator_branch_namer_strategy.target_branch,
      dependency_group: pr_creator.dependency_group,
      includes_security_fixes: branch_namer.includes_security_fixes,
      separator: pr_creator_branch_namer_strategy.separator,
      prefix: pr_creator_branch_namer_strategy.prefix,
      max_length: pr_creator_branch_namer_strategy.max_length,
    )
    branch_namer.instance_variable_set('@strategy', branch_name_strategy)

    Dependabot.logger.info("  branch: #{branch_name_strategy.new_branch_name}")
  end

  pull_request = pr_creator.create

  next unless pull_request

  Dependabot.logger.info(" submitted")

  # Enable GitLab "merge when pipeline succeeds" feature.
  # Merge requests created and successfully tested will be merge automatically.
  if ENV["GITLAB_AUTO_MERGE"]
    g = Gitlab.client(
      endpoint: source.api_endpoint,
      private_token: ENV["GITLAB_ACCESS_TOKEN"]
    )
    #noinspection RubyResolve
    g.accept_merge_request(
      source.repo,
      pull_request.iid,
      merge_when_pipeline_succeeds: true,
      should_remove_source_branch: true
    )
  elsif ENV["AZURE_AUTO_MERGE"] && ENV["AZURE_AUTOCOMPLETE_BY"]
    azure_autocomplete_by = ENV["AZURE_AUTOCOMPLETE_BY"]

    begin
      pull_request_id = JSON.parse(pull_request.body).fetch("pullRequestId")

    rescue KeyError
      Dependabot.logger.error("Unexpected PR response #{pull_request.body}")
    else
      Dependabot.logger.info("  autocomplete PR #{pull_request_id}")

      merge_commit_message = updated_deps.map { |d| "Updating #{d.name} (from #{d.previous_version} to #{d.version})" }.join('\n')

      azure_client = Dependabot::Clients::Azure.for_source(
        source: source,
        credentials: credentials
      )

      azure_client.autocomplete_pull_request(
        pull_request_id,
        azure_autocomplete_by,
        merge_commit_message,
        delete_source_branch = true,
        squash_merge = true,
        merge_strategy = "squash",
        trans_work_items = true,
        ignore_config_ids = []
      )

      Dependabot.logger.info("  autocompletion set")
    end
  end
end

Dependabot.logger.info("Done")
