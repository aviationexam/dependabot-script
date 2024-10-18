FROM docker.io/library/rust:1.82.0-bookworm AS rust

FROM ghcr.io/dependabot/dependabot-updater-core:0.281.0

ARG CODE_DIR=/home/dependabot/dependabot-script
RUN mkdir -p ${CODE_DIR} && chown dependabot:dependabot ${CODE_DIR}

# Install .NET SDK
ARG DOTNET_LTS_SDK_VERSION=8.0.403
ARG DOTNET_STS_SDK_VERSION_DEPENDABOT=9.0.100-rc.1.24452.12
ARG DOTNET_STS_SDK_VERSION=9.0.100-rc.2.24474.11
ARG DOTNET_SDK_INSTALL_URL=https://dot.net/v1/dotnet-install.sh
ENV DOTNET_INSTALL_DIR=/usr/local/dotnet/current
ENV DOTNET_INSTALL_SCRIPT_PATH=/tmp/dotnet-install.sh
ENV DOTNET_NOLOGO=true
ENV DOTNET_ROOT="${DOTNET_INSTALL_DIR}"
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=true
ENV DOTNET_CLI_TELEMETRY_OPTOUT=true
ENV DOTNET_NUGET_CLIENT_REVISION=dev

# Install Rust
ENV RUSTUP_HOME=/opt/rust
ENV CARGO_HOME=/opt/rust
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
ENV PATH="${PATH}:/opt/rust/bin"

# See https://github.com/nodesource/distributions#installation-instructions
ARG NODEJS_VERSION=20

# Check for updates at https://github.com/npm/cli/releases
# This version should be compatible with the Node.js version declared above. See https://nodejs.org/en/download/releases as well
# TODO: Upgrade to 9.6.7 depending on the outcome of https://github.com/npm/cli/issues/6742
ARG NPM_VERSION=9.6.5

# Check for updates at https://github.com/yarnpkg/berry/releases
ARG YARN_VERSION=4.1.1

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
ENV PATH="${PATH}:${DEPENDABOT_NATIVE_HELPERS_PATH}/terraform/bin:${DEPENDABOT_NATIVE_HELPERS_PATH}/python/bin:${DEPENDABOT_NATIVE_HELPERS_PATH}/go_modules/bin:${DEPENDABOT_NATIVE_HELPERS_PATH}/dep/bin:${DEPENDABOT_NATIVE_HELPERS_PATH}/nuget/bin:${DOTNET_INSTALL_DIR}"
ENV MIX_HOME="${DEPENDABOT_NATIVE_HELPERS_PATH}/hex/mix"
ENV NUGET_SCRATCH="${DEPENDABOT_NATIVE_HELPERS_PATH}/nuget/helpers/tmp"

RUN mkdir -p "$RUSTUP_HOME" && chown dependabot:dependabot "$RUSTUP_HOME"

# Install .NET SDK dependencies
RUN apt update && \
  apt install -y --no-install-recommends libicu-dev=70.1-2 && \
  rm -rf /var/lib/apt/lists/*

RUN cd /tmp && \
    curl --location --output "${DOTNET_INSTALL_SCRIPT_PATH}" "${DOTNET_SDK_INSTALL_URL}" && \
    chmod +x "${DOTNET_INSTALL_SCRIPT_PATH}" && \
    mkdir -p "${DOTNET_INSTALL_DIR}" && \
    "${DOTNET_INSTALL_SCRIPT_PATH}" --version "${DOTNET_LTS_SDK_VERSION}" --install-dir "${DOTNET_INSTALL_DIR}" && \
    "${DOTNET_INSTALL_SCRIPT_PATH}" --version "${DOTNET_STS_SDK_VERSION}" --install-dir "${DOTNET_INSTALL_DIR}" && \
    "${DOTNET_INSTALL_SCRIPT_PATH}" --version "${DOTNET_STS_SDK_VERSION_DEPENDABOT}" --install-dir "${DOTNET_INSTALL_DIR}" && \
    rm dotnet-install.sh && \
    chown -R dependabot:dependabot "${DOTNET_INSTALL_DIR}/sdk"

RUN dotnet --list-runtimes
RUN dotnet --list-sdks

# Install Node and npm
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODEJS_VERSION.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g npm@$NPM_VERSION \
  && rm -rf ~/.npm

# Install yarn berry and set it to a stable version
RUN corepack prepare yarn@$YARN_VERSION --activate

USER dependabot

RUN sh -c "$(curl -fsSL https://aka.ms/install-artifacts-credprovider.sh)"

COPY --chown=dependabot:dependabot Gemfile Gemfile.lock ${CODE_DIR}/
WORKDIR ${CODE_DIR}

RUN bundle config set --local path "vendor" \
  && bundle install --jobs 4 --retry 3

COPY --chown=dependabot:dependabot . ${CODE_DIR}

RUN mkdir -p ${DEPENDABOT_NATIVE_HELPERS_PATH}/npm_and_yarn && \
    cp -r $(bundle info --path dependabot-npm_and_yarn)/helpers ${DEPENDABOT_NATIVE_HELPERS_PATH}/npm_and_yarn/helpers && \
    bash ${DEPENDABOT_NATIVE_HELPERS_PATH}/npm_and_yarn/helpers/build

RUN mkdir -p ${DEPENDABOT_NATIVE_HELPERS_PATH}/nuget && \
    cp -r $(bundle info --path dependabot-nuget)/helpers ${DEPENDABOT_NATIVE_HELPERS_PATH}/nuget/helpers && \
    cd ${DEPENDABOT_NATIVE_HELPERS_PATH}/nuget/helpers/lib && \
    git clone https://github.com/NuGet/NuGet.Client.git NuGet.Client && \
    cd NuGet.Client && \
    git checkout ${DOTNET_NUGET_CLIENT_REVISION} && \
    ls -la ${DEPENDABOT_NATIVE_HELPERS_PATH}/nuget/helpers && \
    cat ${DEPENDABOT_NATIVE_HELPERS_PATH}/nuget/helpers/build && \
    bash ${DEPENDABOT_NATIVE_HELPERS_PATH}/nuget/helpers/build

COPY --from=rust /usr/local/rustup $RUSTUP_HOME
COPY --from=rust /usr/local/cargo $CARGO_HOME

ENTRYPOINT ["bundle", "exec", "ruby", "./generic-update-script.rb"]
