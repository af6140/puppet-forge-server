FROM alpine:3.3
MAINTAINER af6140 <daweiwang.gatekeeper@gmail.com>
# Based on 
# http://blog.codeship.com/build-minimal-docker-container-ruby-apps/

ENV OS_PACKAGES bash git ruby-dev build-base
#bash git curl-dev ruby-dev build-base
ENV RUBY_PACKAGES ruby ruby-io-console ruby-bundler

# Update and install all of the required packages.
# At the end, remove the apk cache
RUN apk update && \
    apk upgrade && \
    apk add $OS_PACKAGES && \
    apk add $RUBY_PACKAGES && \
    rm -rf /var/cache/apk/*

RUN mkdir -p /usr/app/puppet-forge-server
WORKDIR /usr/app/puppet-forge-server

COPY . /usr/app/puppet-forge-server
RUN bundle install
RUN bundle exec rake install
RUN rm -rf .git

RUN apk del ruby-dev make g++ gcc libc-dev musl-dev

VOLUME /var/cache/puppet-forge-server
VOLUME /var/log/puppet-forge-server

ENTRYPOINT ["/usr/app/puppet-forge-server/bin/run_forge_server.sh"]