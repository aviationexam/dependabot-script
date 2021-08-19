FROM dependabot/dependabot-core:0.160.0

ARG CODE_DIR=/home/dependabot/dependabot-script
RUN mkdir -p ${CODE_DIR}
COPY --chown=dependabot:dependabot Gemfile Gemfile.lock ${CODE_DIR}/
WORKDIR ${CODE_DIR}

ENV DEPENDABOT_NATIVE_HELPERS_PATH="${CODE_DIR}/native-helpers"
ENV PATH="${PATH}:${DEPENDABOT_NATIVE_HELPERS_PATH}/terraform/bin:${DEPENDABOT_NATIVE_HELPERS_PATH}/python/bin:${DEPENDABOT_NATIVE_HELPERS_PATH}/go_modules/bin:${DEPENDABOT_NATIVE_HELPERS_PATH}/dep/bin"
ENV MIX_HOME="${DEPENDABOT_NATIVE_HELPERS_PATH}/hex/mix"

RUN bundle config set --local path "vendor" \
  && bundle install --jobs 4 --retry 3

COPY --chown=dependabot:dependabot . ${CODE_DIR}

RUN mkdir -p ${DEPENDABOT_NATIVE_HELPERS_PATH}/{terraform,python,dep,go_modules,hex,composer,npm_and_yarn} && \
    cp -r $(bundle show dependabot-npm_and_yarn)/helpers ${DEPENDABOT_NATIVE_HELPERS_PATH}/npm_and_yarn/helpers && \
    ${DEPENDABOT_NATIVE_HELPERS_PATH}/npm_and_yarn/helpers/build ${DEPENDABOT_NATIVE_HELPERS_PATH}/npm_and_yarn

ENTRYPOINT ["bundle", "exec", "ruby", "./generic-update-script.rb"]
