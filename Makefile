
NAME := ChatFilter
VERSION := $(shell grep -w Version ChatFilter.toc | cut -d: -f2 | xargs)
FILENAME := "$(NAME) v$(VERSION).zip"

all: release

release:
	rm -f $(FILENAME)
	zip -r $(FILENAME) . -x "*.git*" -x Makefile -x .DS_Store
	unzip -l $(FILENAME)

tag:
	git tag -a v$(VERSION) -m v$(VERSION) --force HEAD
	git push origin v$(VERSION) --force
