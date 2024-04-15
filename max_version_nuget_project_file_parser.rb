# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/nuget/version"

module Dependabot
  module Nuget

    class MaxVersionNugetProjectFileParser
      extend T::Sig

      DEPENDABOT_PACKAGE_VERSION_SELECTOR = "ItemGroup > DependabotPackageVersion"

      PROPERTY_REGEX      = /\$\((?<property>.*?)\)/
      ITEM_REGEX          = /\@\((?<property>.*?)\)/

      sig { params(dependency_files: T::Array[DependencyFile]).void }
      def initialize(dependency_files:)
        @dependency_files       = dependency_files
      end

      sig { returns(T::Hash[String, Version]) }
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

                if dependabot_max_version != nil
                  package_max_versions[name.downcase] = Version.new(dependabot_max_version)
                end
              end
            end
            package_max_versions
          end
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def directory_packages_props_files
        dependency_files.select { |df| df.name.match?(/[Dd]irectory.[Pp]ackages.props/) }
      end

      sig { params(dependency_node: Nokogiri::XML::Node, project_file: DependencyFile).returns(T.nilable(String)) }
      def dependency_name(dependency_node, project_file)
        raw_name = get_attribute_value(dependency_node, "Include") ||
          get_attribute_value(dependency_node, "Update")
        return unless raw_name

        # If the item contains @(ItemGroup) then ignore as it
        # updates a set of ItemGroup elements
        return if raw_name.match?(ITEM_REGEX)

        evaluated_value(raw_name, project_file)
      end

      sig { params(node: Nokogiri::XML::Node).returns(T.nilable(String)) }
      def get_node_max_version_value(node)
        get_attribute_value(node, "MaxVersion")
      end

      sig { params(node: Nokogiri::XML::Node, attribute: String).returns(T.nilable(String)) }
      def get_attribute_value(node, attribute)
        value =
          node.attribute(attribute)&.value&.strip ||
            node.at_xpath("./#{attribute}")&.content&.strip ||
            node.attribute(attribute.downcase)&.value&.strip ||
            node.at_xpath("./#{attribute.downcase}")&.content&.strip

        value == "" ? nil : value
      end

      sig { params(value: String, project_file: Dependabot::DependencyFile).returns(String) }
      def evaluated_value(value, project_file)
        return value unless value.match?(PROPERTY_REGEX)

        property_name = T.must(value.match(PROPERTY_REGEX)&.named_captures&.fetch("property"))
        property_details = details_for_property(property_name, project_file)

        # Don't halt parsing for a missing property value until we're
        # confident we're fetching property values correctly
        return value unless property_details&.fetch(:value)

        value.gsub(PROPERTY_REGEX, property_details.fetch(:value))
      end

      sig do
        params(property_name: String, project_file: Dependabot::DependencyFile)
          .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
      end
      def details_for_property(property_name, project_file)
        property_value_finder
          .property_details(
            property_name: property_name,
            callsite_file: project_file
          )
      end

      sig { returns(PropertyValueFinder) }
      def property_value_finder
        @property_value_finder ||=
          T.let(PropertyValueFinder.new(dependency_files: dependency_files), T.nilable(PropertyValueFinder))
      end
    end
  end
end