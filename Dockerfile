FROM dependabot/dependabot-core

ADD . /home/dependabot/dependabot-script

WORKDIR /home/dependabot/dependabot-script

RUN bundle install -j 3 --path vendor

RUN cp -r $(bundle show dependabot-npm_and_yarn)/helpers $DEPENDABOT_NATIVE_HELPERS_PATH/npm_and_yarn/helpers
RUN $DEPENDABOT_NATIVE_HELPERS_PATH/npm_and_yarn/helpers/build $DEPENDABOT_NATIVE_HELPERS_PATH/npm_and_yarn

ENTRYPOINT ["bundle", "exec", "ruby", "./generic-update-script.rb"]
