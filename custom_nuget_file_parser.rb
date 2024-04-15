require "dependabot/nuget/file_parser"

module Dependabot
  module Nuget
    class CustomFileParser < Dependabot::Nuget::FileParser
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        workspace_path = project_files.first&.directory
        return [] unless workspace_path

        # run discovery for the repo
        CustomNativeHelpers.run_nuget_discover_tool(repo_root: T.must(repo_contents_path),
                                                    workspace_path: workspace_path,
                                                    output_path: DiscoveryJsonReader.discovery_file_path,
                                                    credentials: credentials)

        discovered_dependencies.dependencies
      end
    end
  end
end

Dependabot::FileParsers.register("nuget", Dependabot::Nuget::CustomFileParser)