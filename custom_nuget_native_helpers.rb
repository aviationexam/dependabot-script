# frozen_string_literal: true

require "dependabot/nuget/native_helpers"

module Dependabot
  module Nuget
    module CustomNativeHelpers

      # rubocop:disable Metrics/MethodLength
      def self.run_nuget_updater_tool(repo_root:, proj_path:, dependency:, is_transitive:, credentials:)
        exe_path = File.join(Dependabot::Nuget::NativeHelpers.native_helpers_root, "NuGetUpdater", "NuGetUpdater.Cli")
        command_parts = [
          exe_path,
          "update",
          "--repo-root",
          repo_root,
          "--solution-or-project",
          proj_path,
          "--dependency",
          dependency.name,
          "--new-version",
          dependency.version,
          "--previous-version",
          dependency.previous_version,
          is_transitive ? "--transitive" : nil,
          "--verbose"
        ].compact

        command = Shellwords.join(command_parts)

        fingerprint = [
          exe_path,
          "update",
          "--repo-root",
          "<repo-root>",
          "--solution-or-project",
          "<path-to-solution-or-project>",
          "--dependency",
          "<dependency-name>",
          "--new-version",
          "<new-version>",
          "--previous-version",
          "<previous-version>",
          is_transitive ? "--transitive" : nil,
          "--verbose"
        ].compact.join(" ")

        nuget_credentials = credentials.select { |cred| cred["type"] == "nuget_feed" }

        env = {}
        if nuget_credentials.any?
          endpoint_credentials = []

          nuget_credentials.each do |c|
            next unless c["token"]

            exploded_token = T.must(c["token"]).split(":", 2)

            next unless exploded_token.length == 2

            username = exploded_token[0]
            password = exploded_token[1]

            endpoint_credentials << <<~NUGET_ENDPOINT_CREDENTIAL
              {"endpoint":"#{c['url']}", "username":"#{username}", "password":"#{password}"}
            NUGET_ENDPOINT_CREDENTIAL
          end

          env["VSS_NUGET_EXTERNAL_FEED_ENDPOINTS"] = "{\"endpointCredentials\": [#{endpoint_credentials.join(',')}]}"
        end

        puts "running NuGet updater:\n" + command

        NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials) do
          output = SharedHelpers.run_shell_command(command, allow_unsafe_shell_command: true, env: env, fingerprint: fingerprint)
          puts output
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end