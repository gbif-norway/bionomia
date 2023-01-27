FROM ruby:2.7.1
WORKDIR /code
COPY . /code
RUN apt-get update && \
    apt-get install -y vim build-essential patch ruby-dev zlib1g-dev liblzma-dev libicu-dev libmagic-dev mariadb-client
RUN bundle install
