module Dependabot
  class PullRequestCreator
    require "dependabot/pull_request_creator/azure"

    class CustomAzure < Dependabot::PullRequestCreator::Azure
      extend T::Sig

      #sig { returns(Dependabot::Clients::Azure) }
      #def azure_client_for_source
      #  @azure_client_for_source ||= Dependabot::Clients::CustomAzure.for_source(
      #    source: source,
      #    credentials: credentials
      #  )
      #end
    end
  end
end