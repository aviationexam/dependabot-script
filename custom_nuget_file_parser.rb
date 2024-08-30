require "dependabot/nuget/file_parser"

module Dependabot
  module Nuget
    class CustomFileParser < Dependabot::Nuget::FileParser
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        return [] unless repo_contents_path

        key = NativeDiscoveryJsonReader.create_cache_key(dependency_files)
        workspace_path = source&.directory || "/"
        self.class.file_dependency_cache[key] ||=
          begin
            # run discovery for the repo
            discovery_json_path = NativeDiscoveryJsonReader.create_discovery_file_path_from_dependency_files(
              dependency_files
            )
            CustomNativeHelpers.run_nuget_discover_tool(
              repo_root: T.must(repo_contents_path),
              workspace_path: workspace_path,
              output_path: discovery_json_path,
              credentials: credentials
            )

            discovery_json = NativeDiscoveryJsonReader.discovery_json_from_path(discovery_json_path)
            return [] unless discovery_json

            Dependabot.logger.info("Discovery JSON content: #{discovery_json.content}")
            discovery_json_reader = NativeDiscoveryJsonReader.new(
              discovery_json: discovery_json
            )

            # cache discovery results
            NativeDiscoveryJsonReader.set_discovery_from_dependency_files(dependency_files: dependency_files,
                                                                          discovery: discovery_json_reader)

            discovery_json_reader.dependency_set.dependencies
          end

        T.must(self.class.file_dependency_cache[key])
      end
    end
  end
end

Dependabot::FileParsers.register("nuget", Dependabot::Nuget::CustomFileParser)