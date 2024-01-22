# frozen_string_literal: true

require "dependabot/nuget/file_updater"
require "./custom_nuget_native_helpers.rb"

module Dependabot
  module Nuget
    class CustomFileUpdater < Dependabot::Nuget::FileUpdater
      def try_update_projects(dependency)
        update_ran = T.let(false, T::Boolean)

        # run update for each project file
        project_files.each do |project_file|
          project_dependencies = project_dependencies(project_file)
          proj_path = dependency_file_path(project_file)

          next unless project_dependencies.any? { |dep| dep.name.casecmp(dependency.name).zero? }

          CustomNativeHelpers.run_nuget_updater_tool(repo_root: repo_contents_path, proj_path: proj_path,
                                               dependency: dependency, is_transitive: !dependency.top_level?,
                                               credentials: credentials)
          update_ran = true
        end

        update_ran
      end
    end
  end
end

Dependabot::FileUpdaters.register("nuget", Dependabot::Nuget::CustomFileUpdater)