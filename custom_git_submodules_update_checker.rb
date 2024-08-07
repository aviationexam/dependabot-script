require "dependabot/git_submodules/update_checker"

module Dependabot
  module GitSubmodules
    class CustomUpdateChecker < Dependabot::GitSubmodules::UpdateChecker
      extend T::Sig

      sig { returns(T.nilable(String)) }
      def fetch_latest_version
        dependency_source_details = rewrite_dependency_url(dependency.source_details(allowed_types: ["git"]))

        git_commit_checker = Dependabot::GitCommitChecker.new(
          dependency: dependency,
          credentials: credentials,
          dependency_source_details: dependency_source_details
        )

        git_commit_checker.head_commit_for_current_branch
      end

      def rewrite_dependency_url(dependency_source_details)
        if options[:git_submodule_url_rewrite] != nil && options[:git_submodule_url_rewrite].key?(dependency_source_details[:url])
          dependency_source_details[:url] = options[:git_submodule_url_rewrite][dependency_source_details[:url]]
        end

        dependency_source_details
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("submodules", Dependabot::GitSubmodules::CustomUpdateChecker)
