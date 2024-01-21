# frozen_string_literal: true

require "dependabot/nuget/file_parser"
require "dependabot/nuget/file_parser/project_file_parser"
require "dependabot/nuget/version"

module Dependabot
  module Nuget
    class CustomFileParser < Dependabot::Nuget::FileParser
      def project_file_parser
        @project_file_parser ||=
          CustomNugetProjectFileParser.new(
            dependency_files: dependency_files,
            credentials: credentials
          )
      end

      class CustomNugetProjectFileParser < Dependabot::Nuget::FileParser::ProjectFileParser
        def parse_dependencies(project_file)
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          doc = Nokogiri::XML(project_file.content)
          doc.remove_namespaces!
          # Look for regular package references
          doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
            name = dependency_name(dependency_node, project_file)
            req = dependency_requirement(dependency_node, project_file)
            version = dependency_version(dependency_node, project_file)
            prop_name = req_property_name(dependency_node)
            dependabot_max_version = get_node_max_version_value(dependency_node)
            is_dev = dependency_node.name == "DevelopmentDependency"

            dependency = build_dependency(name, req, version, prop_name, project_file, dev: is_dev, max_version: dependabot_max_version)
            dependency_set << dependency if dependency
          end

          add_global_package_references(dependency_set)

          add_transitive_dependencies(project_file, doc, dependency_set)

          # Look for SDK references; see:
          # https://docs.microsoft.com/en-us/visualstudio/msbuild/how-to-use-project-sdk
          add_sdk_references(doc, dependency_set, project_file)

          dependency_set
        end

        def build_dependency(name, req, version, prop_name, project_file, dev: false, max_version: nil)
          return unless name

          # Exclude any dependencies specified using interpolation
          return if [name, req, version].any? { |s| s&.include?("%(") }

          requirement = {
            requirement: req,
            file: project_file.name,
            groups: [dev ? "devDependencies" : "dependencies"],
            source: nil
          }

          if prop_name
            # Get the root property name unless no details could be found,
            # in which case use the top-level name to ease debugging
            root_prop_name = details_for_property(prop_name, project_file)
                               &.fetch(:root_property_name) || prop_name
            requirement[:metadata] = { property_name: root_prop_name }
          end

          if max_version != nil
            if requirement[:metadata] == nil
              requirement[:metadata] = {}
            end

            requirement[:metadata][:max_version] = Version.new(max_version)
          end

          dependency = Dependency.new(
            name: name,
            version: version,
            package_manager: "nuget",
            requirements: [requirement]
          )

          # only include dependency if one of the sources has it
          return unless dependency_has_search_results?(dependency)

          dependency
        end

        def get_node_max_version_value(node)
          get_attribute_value(node, "DependabotMaxVersion")
        end
      end
    end
  end
end

Dependabot::FileParsers::register('nuget', Dependabot::Nuget::CustomFileParser)