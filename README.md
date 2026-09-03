# Stasks

Stasks is a macOS menu bar app that surfaces Claude Code session tasks and focuses the matching iTerm2 tab when you click one.

## Make targets

- `make gen`: run xcodegen to (re)generate `Stasks.xcodeproj` from `project.yml`.
- `make build`: generate the project and build the `Stasks` scheme in Release configuration.
- `make test-core`: run the `StasksCore` package test suite.
- `make test-hooks`: run the hooks test suite.
- `make test`: run `test-core` and `test-hooks`.
- `make run`: build, then launch `Stasks.app`.
- `make install`: build, then copy `Stasks.app` into `/Applications` and launch it.
- `make clean`: remove build artifacts and the package's `.build` directory.

## Manual smoke checklist
