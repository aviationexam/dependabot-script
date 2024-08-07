require "dependabot/pull_request_creator"

module Dependabot
  class CustomPullRequestCreator < Dependabot::PullRequestCreator
    extend T::Sig

    require "./custom_pull_request_creator_azure.rb"

    sig { returns(Dependabot::PullRequestCreator::Azure) }
    def azure_creator
      CustomAzure.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: T.must(message.commit_message),
        pr_description: T.must(message.pr_message),
        pr_name: T.must(message.pr_name),
        author_details: author_details,
        labeler: labeler,
        reviewers: T.cast(reviewers, AzureReviewers),
        assignees: T.cast(assignees, T.nilable(T::Array[String])),
        work_item: T.cast(provider_metadata&.fetch(:work_item, nil), T.nilable(Integer))
      )
    end
  end
end