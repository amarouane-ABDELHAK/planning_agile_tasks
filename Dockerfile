FROM ruby:2.5

ADD plant.tar.xz /plant

WORKDIR /plant

RUN gem install bundler -v 1.15.4 && \
    bundle install 
EXPOSE 3004
