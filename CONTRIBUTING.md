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
make test           # the Daml Script test suites
make validate       # validate the built interface DARs
make lint           # dlint over the Daml sources
make headers-check  # every Daml file carries the license header
make dars           # refresh the committed DARs in dars/ from a local build
make dars-check     # prove the committed DARs match a from-source rebuild
make ci             # headers-check, build, validate, test and dars-check
```

Run `make ci` before opening a pull request. If your change affects an
interface package, run `make dars` and commit the refreshed DARs together with
the source. `dars-check` fails CI when the committed DARs and the source drift
apart.

## Conventions

- Every Daml source file carries the SPDX header that `scripts/check-headers.sh`
  enforces. New files carry it too.
- Doc comments cover what a name does not: a field's meaning, a check's
  ordering, a constraint an implementer has to honour. Keep them short, and do
  not restate the code or repeat the guides in `docs/`.
- The publishing party is the `distributor`, in every view and throughout the
  prose. Earlier drafts said "provider"; do not reintroduce it.
- A breaking change to an interface is a new `-v2` package, not an edit to a
  released `-v1`. See the versioning policy in the [README](README.md).
- All executable code lives in the `canton-data-standard-codecs` utility
  package, none of it in an interface package. An interface package holds
  views and one-line fetch choices: it can never be upgraded, so any code in
  it would be unfixable. The codecs package is built with
  `--force-utility-package`, which makes any two of its versions
  SCU-compatible, so bug fixes there are ordinary version bumps.

## License

By contributing you agree that your contributions are licensed under the
[Apache-2.0](LICENSE) license that covers this repository.
