`env-oracle.cpp` independently regenerates the existing account-free quoted and
unquoted Env fixtures using Qt QJsonDocument and QSettings. It checks exact
`Env=` bytes against the checked-in fixtures and reads each back through Qt to
verify both JSON bytes and string-map values. All writes use QTemporaryDir.

From the source root:

```sh
g++ -fPIC tests/prism/fixtures/env-oracle.cpp -o /tmp/prism-env-oracle $(pkg-config --cflags --libs Qt6Core)
/tmp/prism-env-oracle tests/prism/fixtures
```

Qt 6.12.0: 2 probes PASS. Production FPCUnit tests consume these same fixtures
through `DecodePrismEnv`, checking exact Unicode, quote, backslash and control
values. Other deterministic cases construct isolated scalars synthetically and
cover complete JSON EOF, duplicate decoded keys, case sensitivity, nonstring
values, malformed JSON/Unicode, no partial output and exact size/entry bounds.
The decoder preserves JSON strings including escaped controls and empty keys;
OS environment-variable validation is a later caller's responsibility. No
binding, planner, filesystem or application call site is introduced.
