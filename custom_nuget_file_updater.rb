# frozen_string_literal: true

require "dependabot/nuget/file_updater"
require "./custom_nuget_native_helpers.rb"

module Dependabot
  module Nuget
    class CustomFileUpdater < Dependabot::Nuget::FileUpdater
      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        base_dir = "/"
        SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
          expanded_dependency_details.each do |dep_details|
            file = T.let(dep_details.fetch(:file), String)
            name = T.let(dep_details.fetch(:name), String)
            version = T.let(dep_details.fetch(:version), String)
            previous_version = T.let(dep_details.fetch(:previous_version), String)
            is_transitive = T.let(dep_details.fetch(:is_transitive), T::Boolean)
            CustomNativeHelpers.run_nuget_updater_tool(
              repo_root: T.must(repo_contents_path),
              proj_path: file,
              dependency_name: name,
              version: version,
              previous_version: previous_version,
              is_transitive: is_transitive,
              credentials: credentials
            )
          end

          updated_files = dependency_files.filter_map do |f|
            updated_content = File.read(dependency_file_path(f))
            next if updated_content == f.content

            normalized_content = normalize_content(f, updated_content)
            next if normalized_content == f.content

            next unless FileUpdater.differs_in_more_than_blank_lines?(f.content, normalized_content)

            puts "The contents of file [#{f.name}] were updated."

            updated_file(file: f, content: normalized_content)
          end
          updated_files
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register("nuget", Dependabot::Nuget::CustomFileUpdater)