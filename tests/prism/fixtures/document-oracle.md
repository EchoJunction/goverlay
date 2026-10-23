# Synthetic Qt document boundary oracle

`document-oracle.cpp` creates only synthetic temporary INI files. It is an
optional developer oracle, with no dependency added to the Pascal test runner.
Validated with Qt6Core 6.12.0 on 2026-10-23:

```sh
g++ -fPIC tests/prism/fixtures/document-oracle.cpp -o /tmp/prism-document-fixture-oracle $(pkg-config --cflags --libs Qt6Core)
/tmp/prism-document-fixture-oracle
```

Result: `Qt document oracle: 17 probes passed`.

The probes establish that key names are case sensitive, surrounding ASCII
whitespace is trimmed, but `General` section recognition is case insensitive
and tolerates interior whitespace. `%45nv`/`En%76` key names alias `Env`, while
backslash in a key becomes a separator. `[%General]` and `[%47eneral]` refer
to the literal `General/` group rather than the root settings. Slash in a
section name produces Qt FormatError. Hash within a value is literal;
unquoted semicolon begins an inline comment. Leading hash is key text, not a
whole-line comment: a hash key with terminal backslash or an open quote can
consume the following assignment. The index refuses hash-prefixed lines.
Odd terminal backslash joins
the next line, paired backslashes do not, and an unclosed quote consumes
following lines.

The document index deliberately supports a narrower subset: exactly canonical
`[General]`, ASCII letters/digits/underscore/dot/hyphen names, no encoded names,
no multiline values. Unknown values retain their bytes and permit opaque lists,
QVariant syntax and inline comments, provided quote/continuation boundaries
are unambiguous. Managed values pass the existing strict Qt scalar decoder.
The FPCUnit document tests cover these refusals, complete original byte equality,
byte spans, opaque unknown values and the same version contract for global and
instance settings. ConfigVersion is always required; InstanceType is opaque.
