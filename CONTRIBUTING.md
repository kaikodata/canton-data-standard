# Contributing

This repository holds the versioned Daml interfaces, reference implementations,
and documentation for the Canton Data Standard. It backs a Canton Improvement
Proposal, so a change to an interface is also a change to the standard.

## Before you start

Open an issue before writing code, so the shape of a change is agreed first. A
change under `interfaces/` carries the most weight: the on-ledger view, the
choices, and the upgrade story are the contract every implementer relies on, and
they move deliberately, in step with the CIP. Examples, tests, and documentation
are easier to land.

## Building and testing

Install [dpm](https://docs.digitalasset.com/) (the Daml Package Manager) and a
JDK (17+), then pin the SDK the packages build against:

```bash
dpm install 3.4.11
```

The `Makefile` wraps the common tasks, and `make ci` runs the full gate:

```bash
make build          # dpm build --all
make test           # the Daml Script test suite
make validate       # validate the built interface DARs
make lint           # dlint over the Daml sources
make headers-check  # every Daml file carries the license header
make ci             # headers-check, build, validate and test
```

Run `make ci` before opening a pull request.

## Conventions

- Every Daml source file carries the SPDX header that `scripts/check-headers.sh`
  enforces. New files carry it too.
- Exported types, choices, and fields carry doc comments. The exported API is
  the product, so match the documentation style of the surrounding code.
- A breaking change to an interface is a new `-v2` package, never an edit to a
  released `-v1`. See the versioning policy in the [README](README.md).

## License

By contributing you agree that your contributions are licensed under the
[Apache-2.0](LICENSE) license that covers this repository.
