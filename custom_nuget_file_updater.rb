# frozen_string_literal: true

require "dependabot/nuget/file_updater"
require "./custom_nuget_native_helpers.rb"

module Dependabot
  module Nuget
    class CustomFileUpdater < Dependabot::Nuget::FileUpdater
      sig { params(dependency: Dependency, proj_path: String).void }
      def call_nuget_updater_tool(dependency, proj_path)
        CustomNativeHelpers.run_nuget_updater_tool(repo_root: T.must(repo_contents_path), proj_path: proj_path,
                                                   dependency: dependency, is_transitive: !dependency.top_level?,
                                                   credentials: credentials)

        # Tests need to track how many times we call the tooling updater to ensure we don't recurse needlessly
        # Ideally we should find a way to not run this code in prod
        # (or a better way to track calls made to NativeHelpers)
        @update_tooling_calls ||= T.let({}, T.nilable(T::Hash[String, Integer]))
        key = proj_path + dependency.name
        @update_tooling_calls[key] =
          if @update_tooling_calls[key]
            T.must(@update_tooling_calls[key]) + 1
          else
            1
          end
      end
    end
  end
end

Dependabot::FileUpdaters.register("nuget", Dependabot::Nuget::CustomFileUpdater)