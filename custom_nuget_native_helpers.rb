# frozen_string_literal: true

require "dependabot/nuget/native_helpers"

module Dependabot
  module Nuget
    module CustomNativeHelpers

      # rubocop:disable Metrics/MethodLength
      def self.run_nuget_updater_tool(repo_root:, proj_path:, dependency:, is_transitive:, credentials:)
        exe_path = File.join(Dependabot::Nuget::NativeHelpers.native_helpers_root, "NuGetUpdater", "NuGetUpdater.Cli")
        command = [
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
          is_transitive ? "--transitive" : "",
          "--verbose"
        ].join(" ")

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
          is_transitive ? "--transitive" : "",
          "--verbose"
        ].join(" ")

        nuget_credentials = credentials.select { |cred| cred["type"] == "nuget_feed" }

        env = {}
        if nuget_credentials.any?
          endpoint_credentials = []

          nuget_credentials.each_with_index do |c|
            next unless c["token"]

            nuget_api_token = c["token"]
            if nuget_api_token.start_with?(':')
              nuget_api_token = nuget_api_token[1..]
            end
            endpoint_credentials << "{\"endpoint\":\"#{c["url"]}\", \"username\":\"optional\", \"password\":\"#{nuget_api_token}\"}"
          end

          env["VSS_NUGET_EXTERNAL_FEED_ENDPOINTS"]="{\"endpointCredentials\": [#{endpoint_credentials.join(',')}]}"
        end

        puts "running NuGet updater:\n" + command

        patch_nuget_config_for_action(credentials) do
          output = SharedHelpers.run_shell_command(command, env: env, fingerprint: fingerprint)
          puts output
        end
      end
      # rubocop:enable Metrics/MethodLength

      def self.patch_nuget_config_for_action(credentials, &_block)
        NuGetConfigCredentialHelpers.add_credentials_to_nuget_config(credentials)
        begin
          yield
        rescue StandardError => e
          puts "block causes an exception #{e}: #{e.message}"
        ensure
          NuGetConfigCredentialHelpers.restore_user_nuget_config
        end
      end
    end
  end
end