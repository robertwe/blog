IMAGE ?= blog
RUN   := podman run --rm -v "$(CURDIR):/site"

.PHONY: image lock stamp build serve preview deploy

stamp:          ## write _data/build.yml with the current commit (footer shows it)
	printf 'commit: %s\nfull: %s\nbuilt: %s\n' "$$(git rev-parse --short HEAD)" "$$(git rev-parse HEAD)" "$$(date -u +%Y-%m-%dT%H:%MZ)" > _data/build.yml

image:          ## build the container image (re-run after Gemfile changes)
	podman build -t $(IMAGE) .

lock:           ## regenerate Gemfile.lock inside the container
	$(RUN) -w /site --entrypoint bundle docker.io/library/ruby:3.4 lock --update

build: stamp    ## build the site into docs/
	$(RUN) $(IMAGE)

serve: stamp    ## live preview on http://localhost:4000
	$(RUN) -p 4000:4000 $(IMAGE) serve --host 0.0.0.0 --livereload

preview: stamp  ## like serve, but also renders future-dated (scheduled) posts
	$(RUN) -p 4000:4000 $(IMAGE) serve --host 0.0.0.0 --livereload --future

deploy: build   ## build, then push docs/ to Firebase Hosting
	firebase deploy --only hosting
