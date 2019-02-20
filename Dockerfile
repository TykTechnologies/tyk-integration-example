FROM ruby:2.5-alpine

RUN gem install sinatra excon rack-mount

WORKDIR /usr/src/app
