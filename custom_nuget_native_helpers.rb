# frozen_string_literal: true

require "dependabot/nuget/native_helpers"

module Dependabot
  module Nuget
    module CustomNativeHelpers
      extend T::Sig

      sig do
        params(
          repo_root: String,
          workspace_path: String,
          output_path: String,
          credentials: T::Array[Dependabot::Credential]
        ).void
      end
      def self.run_nuget_discover_tool(repo_root:, workspace_path:, output_path:, credentials:)
        (command, fingerprint) = NativeHelpers.get_nuget_discover_tool_command(repo_root: repo_root,
                                                                               workspace_path: workspace_path,
                                                                               output_path: output_path)

        env = get_env(credentials: credentials)

        puts "running NuGet discovery:\n" + command

        NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials) do
          output = SharedHelpers.run_shell_command(command, allow_unsafe_shell_command: true, env: env, fingerprint: fingerprint)
          puts output
        end
      end

      sig do
        params(
          repo_root: String,
          proj_path: String,
          dependency: Dependency,
          is_transitive: T::Boolean,
          credentials: T::Array[Dependabot::Credential]
        ).void
      end
      def self.run_nuget_updater_tool(repo_root:, proj_path:, dependency:, is_transitive:, credentials:)
        update_result_file_path = NativeHelpers.update_result_file_path

        (command, fingerprint) = NativeHelpers.get_nuget_updater_tool_command(repo_root: repo_root, proj_path: proj_path,
                                                                              dependency: dependency, is_transitive: is_transitive,
                                                                              result_output_path: update_result_file_path)

        env = get_env(credentials: credentials)

        puts "running NuGet updater:\n" + command

        NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials) do
          output = SharedHelpers.run_shell_command(command, allow_unsafe_shell_command: true, env: env, fingerprint: fingerprint)
          puts output

          result_contents = File.read(update_result_file_path)
          Dependabot.logger.info("update result: #{result_contents}")
          result_json = T.let(JSON.parse(result_contents), T::Hash[String, T.untyped])
          ensure_no_errors(result_json)
        end
      end

      sig do
        params(
          credentials: T::Array[Dependabot::Credential]
        ).returns(T::Hash[String, String])
      end
      def self.get_env(credentials:)
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

        env
      end
    end
  end
end