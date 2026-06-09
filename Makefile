
NAME := ChatFilter
VERSION := $(shell grep -w Version ChatFilter.toc | cut -d: -f2)
FILENAME := "$(NAME)$(VERSION).zip"

all: release

release:
	rm -f $(FILENAME)
	zip -r $(FILENAME) . -x "*.git*" -x Makefile -x .DS_Store
	unzip -l $(FILENAME)
