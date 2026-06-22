# Copyright (c) 2026 Challenger Deep SAS. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Build, validate and test the Data Standard packages. CI runs `make ci`;
# the same targets are meant to be run locally during development.

DAR_GLOB := interfaces/*/.daml/dist/*.dar
DAML_PKGS := $(shell find interfaces examples tests tests-crypto tests-paid -name daml.yaml -not -path '*/.daml/*' -exec dirname {} \;)

.PHONY: build test validate lint headers-check clean ci

build:
	dpm build --all

# Run the three test packages in-memory: the token-free `tests` suite, the
# secp256k1 `tests-crypto` suite, and the token-coupled `tests-paid` suite. All
# must run so no path silently stops being exercised in CI.
test:
	cd tests && dpm test
	cd tests-crypto && dpm test
	cd tests-paid && dpm test

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

clean:
	dpm clean --all

ci: headers-check build validate test
