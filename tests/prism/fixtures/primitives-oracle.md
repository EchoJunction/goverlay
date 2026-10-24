These fixtures and oracle programs are account-free and synthetic. Production
units remain pure; only this test utility performs explicit temporary-file I/O.
The FPC generator exclusively creates new files and refuses existing targets.
No real Prism directory or settings should be supplied.

`primitives-global.ini` and `primitives-instance.cfg` were regenerated using
Qt6.12.0. Both require ConfigVersion=1.3. The global Env has two ordered strings,
Unicode/supplementary characters, quoting/backslash and escaped NUL/control/DEL;
Qt emits a quoted scalar. The instance has a single Unicode selector string;
Qt emits its escaped unquoted form. FPCUnit consumes both checked-in fixtures.

From the source root, with FPC and Qt6Core development tools available:

```sh
mkdir -p /tmp/prism-primitives-units
fpc -B -Cr -Co -Ci -Sa -Fu. -FU/tmp/prism-primitives-units -FE/tmp -oprism-primitives-fixtures tests/prism/fixtures/primitives-oracle.lpr
g++ -fPIC tests/prism/fixtures/primitives-oracle.cpp -o /tmp/prism-primitives-qt $(pkg-config --cflags --libs Qt6Core)
primitives_dir=$(mktemp -d /tmp/prism-primitives.XXXXXXXX)
/tmp/prism-primitives-fixtures create "$primitives_dir"
/tmp/prism-primitives-qt "$primitives_dir"
/tmp/prism-primitives-fixtures verify "$primitives_dir"
```

The generator uses production bool/Env encoders and managed span edits to make
separate global CRLF and instance LF/no-final-LF documents. Both emitted Env
scalars are always whole-quoted. The independent C++ oracle reads exact expected
bool/string-map values through QSettings/QJsonDocument, preserves unrelated
section values semantically, then writes new normalized files through QSettings.
It checks that Qt chooses the distinct quoted/unquoted forms. FPC reindexes and
decodes both normalized files to identical ordered strings and bools. Results:
2 create probes, 4 Qt read/normalize probes and 2 FPC parity probes PASS.
Generated normalized files match the checked-in fixtures byte-for-byte.

The pure edit primitive preserves exact unrelated bytes, scalar-surrounding
whitespace and existing physical terminators. Missing keys go immediately before
the next section or at EOF; new lines use the General header's LF/CRLF while
retaining whether the original ended in a newline. Inputs are reindexed before
spans are used, and proposals reindexed before return. Bool/value semantics,
defaults and environment-variable policy beyond the strict codecs belong to
later callers.
