PREFIX ?= /usr/local
DESTDIR ?=
VERSION := $(shell sed -n 's/^version = "\([^"]*\)"/\1/p' alire.toml)
SCHEMAS := $(wildcard docs/*.schema.json)

ifeq ($(strip $(VERSION)),)
$(error Unable to read the release version from alire.toml)
endif

.PHONY: build test install uninstall package clean-package print-version

print-version:
	@printf '%s\n' '$(VERSION)'

build:
	alr -n build

test:
	alr -n test
	./bin/check_all

install: build
	install -Dm755 bin/ada-quality $(DESTDIR)$(PREFIX)/bin/ada-quality
	install -Dm644 docs/ada-quality.1 $(DESTDIR)$(PREFIX)/share/man/man1/ada-quality.1
	mkdir -p $(DESTDIR)$(PREFIX)/share/ada-quality/schemas
	install -m644 $(SCHEMAS) $(DESTDIR)$(PREFIX)/share/ada-quality/schemas/
	mkdir -p $(DESTDIR)$(PREFIX)/share/bash-completion/completions
	./bin/ada-quality completion bash > $(DESTDIR)$(PREFIX)/share/bash-completion/completions/ada-quality
	mkdir -p $(DESTDIR)$(PREFIX)/share/zsh/site-functions
	./bin/ada-quality completion zsh > $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_ada-quality
	mkdir -p $(DESTDIR)$(PREFIX)/share/fish/vendor_completions.d
	./bin/ada-quality completion fish > $(DESTDIR)$(PREFIX)/share/fish/vendor_completions.d/ada-quality.fish

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/ada-quality
	rm -f $(DESTDIR)$(PREFIX)/share/man/man1/ada-quality.1
	rm -rf $(DESTDIR)$(PREFIX)/share/ada-quality
	rm -f $(DESTDIR)$(PREFIX)/share/bash-completion/completions/ada-quality
	rm -f $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_ada-quality
	rm -f $(DESTDIR)$(PREFIX)/share/fish/vendor_completions.d/ada-quality.fish

package: build
	mkdir -p dist/ada-quality-$(VERSION)/bin dist/ada-quality-$(VERSION)/docs
	install -m755 bin/ada-quality dist/ada-quality-$(VERSION)/bin/
	install -m644 README.md LICENSE CHANGELOG.md dist/ada-quality-$(VERSION)/
	install -m644 docs/ada-quality.1 $(SCHEMAS) dist/ada-quality-$(VERSION)/docs/
	tar -C dist -czf dist/ada-quality-$(VERSION)-linux-x86_64.tar.gz ada-quality-$(VERSION)

clean-package:
	rm -rf dist
