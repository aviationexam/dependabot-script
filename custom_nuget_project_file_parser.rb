# frozen_string_literal: true

require "dependabot/nuget/file_parser"
require "dependabot/nuget/file_parser/project_file_parser"
require "dependabot/nuget/version"

module Dependabot
  module Nuget
    class CustomFileParser < Dependabot::Nuget::FileParser
      def project_file_parser
        @project_file_parser ||= CustomNugetProjectFileParser.new(
          dependency_files: dependency_files,
          credentials: credentials,
          repo_contents_path: @repo_contents_path
        )
      end

      class CustomNugetProjectFileParser < Dependabot::Nuget::FileParser::ProjectFileParser
        DEPENDABOT_PACKAGE_VERSION_SELECTOR = "ItemGroup > DependabotPackageVersion"

        def package_max_versions
          @package_max_versions ||=
            begin
              package_max_versions = {}
              directory_packages_props_files.each do |file|
                doc = Nokogiri::XML(file.content)
                doc.remove_namespaces!
                doc.css(DEPENDABOT_PACKAGE_VERSION_SELECTOR).each do |package_node|
                  name = dependency_name(package_node, file)
                  dependabot_max_version = get_node_max_version_value(package_node)

                  package_max_versions[name.downcase] = Version.new(dependabot_max_version)
                end
              end
              package_max_versions
            end
        end

        def get_node_max_version_value(node)
          get_attribute_value(node, "MaxVersion")
        end
      end
    end
  end
end

Dependabot::FileParsers::register('nuget', Dependabot::Nuget::CustomFileParser)