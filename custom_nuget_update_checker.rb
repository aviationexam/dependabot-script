# frozen_string_literal: true

require "dependabot/nuget/update_checker"
require "dependabot/nuget/update_checker/property_updater"
require "dependabot/nuget/update_checker/version_finder"
require "dependabot/nuget/version"

module Dependabot
  module Nuget
    class CustomUpdateChecker < Dependabot::Nuget::UpdateChecker
      def version_finder
        @version_finder ||=
          CustomVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: @raise_on_ignored,
            security_advisories: security_advisories,
            package_max_versions: options[:package_max_versions]
          )
      end

      def property_updater
        @property_updater ||=
          CustomPropertyUpdater.new(
            dependency: dependency,
            dependency_files: dependency_files,
            target_version_details: latest_version_details,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: @raise_on_ignored
          )
      end

      class CustomVersionFinder < Dependabot::Nuget::UpdateChecker::VersionFinder
        attr_reader :package_max_versions

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, raise_on_ignored: false,
                       security_advisories:, package_max_versions:)
          @package_max_versions = package_max_versions

          super(
            dependency: dependency, dependency_files: dependency_files, credentials: credentials,
            ignored_versions: ignored_versions, raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          )
        end

        def v3_nuget_listings
          return @filtered_v3_nuget_listings unless @filtered_v3_nuget_listings.nil?

          max_version = package_max_versions[@dependency.name]

          @filtered_v3_nuget_listings ||=
            super.map{ |package|
              if max_version != nil
                package["versions"] = package["versions"].select{ |version| Version.new(version) < max_version }.to_set
              end

              package
            }
        end
      end

      class CustomPropertyUpdater < Dependabot::Nuget::UpdateChecker::PropertyUpdater
      end
    end
  end
end

Dependabot::UpdateCheckers.register("nuget", Dependabot::Nuget::CustomUpdateChecker)