# GOverlay Local Test Suite

Automated regression tests for GOverlay, designed to run locally before every
commit. No X server, no display, no mouse synthesis: tests run in-process
against the real application code.

## Architecture

```
tests/
  common/   test_isolation.pas  - shared sandbox: fresh mock HOME, seed
                                  config, re-exec so the FPC runtime sees
                                  the mocked environment from process start
  logic/    logic_tests         - headless fpcunit tests for config logic
                                  (driver preference, OptiScaler INI
                                  round-trips). No GUI needed.
  gui/      gui_tests           - instantiates the real Tgoverlayform with
                                  Qt6 offscreen platform, drives controls
                                  programmatically (OnClick invocations,
                                  TRadioButton.Checked) and asserts on
                                  config files + control state.
```

Key properties:

- **Deterministic**: `GOVERLAY_TEST=1` makes the app skip network update
  checks, background download threads, and the changelog fetch on startup.
- **Isolated**: every run uses a fresh temporary `$HOME`. Real user
  configuration is never touched. The sandbox is deleted on success and
  preserved (path printed) on failure.
- **Falsifiable**: toggle tests assert both transitions, so pre-seeded
  fixture values can never satisfy an assertion by accident.

## Running

```bash
make test          # builds and runs both layers
make test-prism    # standalone Prism discovery fixtures (FPC only, no LCL)
make test-logic    # logic layer only
make test-gui      # GUI wiring layer only
```

## Commit gate

Install the pre-commit hook to block commits when tests fail:

```bash
sh tests/install-hook.sh
```

Bypass in emergencies with `git commit --no-verify`.

## Writing new tests

- Logic tests: add a `TTestCase` in `logic/logic_test_cases.pas` and
  `RegisterTest` it. Runs in milliseconds, no display.
- GUI tests: add to `gui/gui_test_cases.pas`. The form is created once
  before the suite runs; access controls via `goverlayform.<controlName>`
  and invoke `.OnClick(control)` / set `.Checked` to exercise the real
  `.lfm` event bindings.

Prism discovery tests use the production `prismprovider` unit with temporary
native, Flatpak and custom data roots. The sanitized `modern-instance.cfg`
fixture was emitted by Qt QSettings for the Prism 11.1.1 schema (source commit
`7d2d3c1ec6fcf8255ebacd02d9f792688575dfb4`), with `InstanceType=OneSix`
added to identify a Minecraft instance. Its opaque Env JSON is deliberately
ignored during discovery. Additional malformed and boundary fixtures are built
in temporary directories by the tests. A recursive path/content snapshot checks
that discovery creates, deletes and changes no fixture files or directories.

Discovery supports modern `ConfigVersion=1.3` only. Missing UUIDs use a scoped
full instance-directory identity; moving such a folder or changing its configured
instance directory changes its identity. Duplicate UUIDs in
one data root are all rejected. A truncated root publishes no instances because
UUID uniqueness cannot be established; discovery then stops at its global scan
budget. Test roots are created exclusively with mode 0700 and cleanup checks
the original directory identity. Symlinks and `..` components are refused;
explicit custom roots and an absolute configured `InstanceDir` may point outside
the default root. Discovery provides no activation, writes or runtime overlay
verification. It rechecks paths before reading but does not claim protection
against an adversary concurrently replacing ancestor directories.
