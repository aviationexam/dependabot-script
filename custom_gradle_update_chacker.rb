# frozen_string_literal: true

require "dependabot/gradle/update_checker"
require "dependabot/gradle/update_checker/version_finder"

module Dependabot
  module Gradle
    class CustomUpdateChecker < Dependabot::Gradle::UpdateChecker
      class VersionFinder < Dependabot::Gradle::UpdateChecker::VersionFinder
        def repositories
          return @repositories if @repositories

          details = if plugin?
                      plugin_repository_details +
                        credentials_repository_details
                    else
                      dependency_repository_details +
                        credentials_repository_details
                    end

          @repositories =
            details.reject do |repo|
              next if repo["auth_headers"] && !repo["auth_headers"].empty?

              # Reject this entry if an identical one with non-empty auth_headers exists
              details.any? { |r| r["url"] == repo["url"] && r["auth_headers"] != {} }
            end
        end
      end

      def version_finder
        @version_finder ||=
          VersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("gradle", Dependabot::Gradle::CustomUpdateChecker)
