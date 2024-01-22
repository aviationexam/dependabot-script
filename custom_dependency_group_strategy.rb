# frozen_string_literal: true

require "dependabot/pull_request_creator/branch_namer/dependency_group_strategy"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      class CustomDependencyGroupStrategy < Dependabot::PullRequestCreator::BranchNamer::DependencyGroupStrategy
        def new_branch_name
          sanitize_branch_name(File.join(prefixes, @dependency_group.name))
        end
      end
    end
  end
end
