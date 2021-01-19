FROM dependabot/dependabot-core

ADD . /home/dependabot/dependabot-script

WORKDIR /home/dependabot/dependabot-script

RUN bundle install -j 3 --path vendor

ENTRYPOINT ["bundle", "exec", "ruby", "./generic-update-script.rb"]
