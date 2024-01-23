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
        DEPENDABOT_PACKAGE_VERSION_SELECTOR = "ItemGroup > DependabotPackageVersion"

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
            is_dev = dependency_node.name == "DevelopmentDependency"

            dependency = build_dependency(name, req, version, prop_name, project_file, dev: is_dev)
            dependency_set << dependency if dependency
          end

          doc.css(DEPENDABOT_PACKAGE_VERSION_SELECTOR).each do |dependency_node|
            name = dependency_name(dependency_node, project_file)
            dependabot_max_version = get_node_max_version_value(dependency_node)

            dep = dependency_set.dependency_for_name(name)
            dep.metadata[:max_version] = Version.new(dependabot_max_version)
          end

          add_global_package_references(dependency_set)

          add_transitive_dependencies(project_file, doc, dependency_set)

          # Look for SDK references; see:
          # https://docs.microsoft.com/en-us/visualstudio/msbuild/how-to-use-project-sdk
          add_sdk_references(doc, dependency_set, project_file)

          dependency_set
        end

        def get_node_max_version_value(node)
          get_attribute_value(node, "MaxVersion")
        end
      end
    end
  end
end

Dependabot::FileParsers::register('nuget', Dependabot::Nuget::CustomFileParser)