IMAGE ?= blog
RUN   := podman run --rm -v "$(CURDIR):/site"

.PHONY: image lock build serve deploy

image:          ## build the container image (re-run after Gemfile changes)
	podman build -t $(IMAGE) .

lock:           ## regenerate Gemfile.lock inside the container
	$(RUN) -w /site --entrypoint bundle docker.io/library/ruby:3.4 lock --update

build:          ## build the site into docs/
	$(RUN) $(IMAGE)

serve:          ## live preview on http://localhost:4000
	$(RUN) -p 4000:4000 $(IMAGE) serve --host 0.0.0.0 --livereload

deploy: build   ## build, then push docs/ to Firebase Hosting
	firebase deploy --only hosting
