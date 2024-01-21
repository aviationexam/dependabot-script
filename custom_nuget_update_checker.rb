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
            security_advisories: security_advisories
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
        def v3_nuget_listings
          return @filtered_v3_nuget_listings unless @filtered_v3_nuget_listings.nil?

          max_version = @dependency.requirements
                                   .map { |req| req[:metadata] }.reject(&:nil?)
                                   .map { |metadata| metadata[:max_version] }.reject(&:nil?)
                                   .sort.first

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