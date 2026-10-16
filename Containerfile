# Build image for the site: Ruby + gems baked in, source mounted at run time.
#   podman build -t blog .
#   podman run --rm -v "$PWD:/site" blog            # -> docs/
#   podman run --rm -v "$PWD:/site" -p 4000:4000 blog serve --host 0.0.0.0
FROM docker.io/library/ruby:3.4
WORKDIR /site
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4
ENTRYPOINT ["bundle", "exec", "jekyll"]
CMD ["build", "-d", "docs"]
