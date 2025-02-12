FROM ruby:2.5.0-alpine


RUN apk add --no-cache build-base nodejs
  

RUN mkdir /app
WORKDIR /app



COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 1.17.3
RUN bundle install


COPY . .

EXPOSE 4567

CMD ["bundle", "exec", "middleman", "server"]
