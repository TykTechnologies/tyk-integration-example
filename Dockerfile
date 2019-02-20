FROM ruby:2.5-alpine

RUN gem install sinatra excon

WORKDIR /usr/src/app
