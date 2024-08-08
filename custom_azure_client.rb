# typed: strict
# frozen_string_literal: true

module Dependabot
  module Clients
    class CustomAzure < Dependabot::Clients::Azure
      extend T::Sig

      sig do
        params(
          branch_name: String,
          base_commit: String,
          commit_message: String,
          files: T::Array[Dependabot::DependencyFile],
          author_details: T.nilable(T::Hash[Symbol, String])
        )
          .returns(T.untyped)
      end
      def create_commit(branch_name, base_commit, commit_message, files,
                        author_details)
        submodule_files = files.filter { |dependency| dependency.type == 'submodule' }
        non_submodule_files = files.filter { |dependency| dependency.type != 'submodule' }

        response = nil
        if non_submodule_files.count > 0
          response = create_commit_with_changes(
            branch_name, base_commit, commit_message,
            non_submodule_files.map { |file|
              {
                changeType: "edit",
                item: { path: file.path },
                newContent: {
                  content: Base64.encode64(file.content),
                  contentType: "base64encoded"
                }
              }
            },
            author_details
          )

          base_commit = JSON.parse(response.body).fetch("refUpdates")[0].fetch("newObjectId")
        end

        if submodule_files.count > 0
          response = create_commit_with_changes(
            branch_name, base_commit, commit_message,
            submodule_files.map { |file|
              {
                changeType: "delete",
                item: { path: file.path }
              }
            },
            author_details
          )

          base_commit = JSON.parse(response.body).fetch("refUpdates")[0].fetch("newObjectId")

          response = create_commit_with_changes(
            branch_name, base_commit, commit_message,
            submodule_files.map { |file|
              {
                changeType: "add",
                item: { path: file.path },
                newContent: {
                  content: Base64.encode64(T.must(file.content)),
                  contentType: "base64encoded"
                }
              }
            },
            author_details
          )
        end

        response
      end

      sig do
        params(
          branch_name: String,
          base_commit: String,
          commit_message: String,
          changes: T::Array[T.untyped],
          author_details: T.nilable(T::Hash[Symbol, String])
        )
          .returns(T.untyped)
      end
      def create_commit_with_changes(branch_name, base_commit, commit_message, changes,
                                     author_details)
        content = {
          refUpdates: [
            { name: "refs/heads/" + branch_name, oldObjectId: base_commit }
          ],
          commits: [
            {
              comment: commit_message,
              author: author_details,
              changes: changes
            }.compact
          ]
        }

        post(T.must(source.api_endpoint) + source.organization + "/" + source.project +
               "/_apis/git/repositories/" + source.unscoped_repo +
               "/pushes?api-version=5.0", content.to_json)
      end
    end
  end
end
