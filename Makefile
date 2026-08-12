# Copyright (c) 2026 Challenger Deep SAS. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Build, validate and test the Data Standard packages. CI runs `make ci`;
# the same targets are meant to be run locally during development.

DAR_GLOB := interfaces/*/.daml/dist/*.dar
DAML_PKGS := $(shell find interfaces examples tests tests-codecs tests-crypto -name daml.yaml -not -path '*/.daml/*' -exec dirname {} \;)

.PHONY: build test validate lint headers-check clean ci dars dars-check

build:
	dpm build --all

# Run the three test packages in-memory: the token-free `tests` suite, the
# crypto-free `tests-codecs` golden-vector suite, and the secp256k1
# `tests-crypto` suite. All must run so no path silently stops being
# exercised in CI.
test:
	cd tests && dpm test
	cd tests-codecs && dpm test
	cd tests-crypto && dpm test

validate:
	@for dar in $(DAR_GLOB); do dpm validate-dar "$$dar"; done

# Lint each package from its own directory: damlc lint resolves cross-package
# imports through that package's built database, which a single whole-tree
# invocation cannot.
lint:
	@set -e; for pkg in $(DAML_PKGS); do \
	  echo "lint $$pkg"; \
	  ( cd "$$pkg" && dpm damlc lint $$(find daml -name '*.daml') ); \
	done

headers-check:
	@./scripts/check-headers.sh

# Refresh the committed DARs from a local build. The dars/ directory is the
# distribution channel DA asked for (DARs directly obtainable from the repo);
# it is committed by hand as part of a release PR and policed by dars-check.
dars: build
	@mkdir -p dars
	@cp $(DAR_GLOB) dars/
	@ls -1 dars/*.dar

# Prove the committed DARs are in sync with the source next to them: rebuild
# from source and compare package ids (the package id is the content hash, so
# any source drift flips it). Fails on a missing, stale, or diverged DAR.
dars-check:
	@set -e; \
	found=0; \
	for dar in $(DAR_GLOB); do \
	  found=1; \
	  name=$$(basename "$$dar"); \
	  if [ ! -f "dars/$$name" ]; then echo "dars-check: missing committed DAR dars/$$name"; exit 1; fi; \
	  built=$$(dpm inspect-dar "$$dar" --json | jq -r .main_package_id); \
	  committed=$$(dpm inspect-dar "dars/$$name" --json | jq -r .main_package_id); \
	  if [ "$$built" != "$$committed" ]; then \
	    echo "dars-check: $$name diverged (committed $$committed != built $$built)"; exit 1; \
	  fi; \
	  echo "dars-check: $$name OK ($$built)"; \
	done; \
	if [ "$$found" = "0" ]; then echo "dars-check: no built interface DARs found, run make build"; exit 1; fi; \
	for dar in dars/*.dar; do \
	  name=$$(basename "$$dar"); \
	  if ! ls interfaces/*/.daml/dist/"$$name" >/dev/null 2>&1; then \
	    echo "dars-check: stale committed DAR $$dar has no source package"; exit 1; \
	  fi; \
	done

clean:
	dpm clean --all

ci: headers-check build validate test dars-check
