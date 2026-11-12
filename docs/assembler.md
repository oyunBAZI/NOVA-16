# Assembler
`n16asm SOURCE --out ROM [--symbols MAP]` emits a checked N16R container.
Diagnostics include path, line, column (currently 1), source line and stable
error name. Symbols are case sensitive; instructions/registers/directives
are case insensitive. A semicolon outside a quoted string starts a comment.

Expressions: decimal, 0x hex, 0b binary, signed literals, symbols, and a single
`+ numeric` or `- numeric` suffix. Constants use `.equ name, expression` and
must be defined before use in layout directives. Forward instruction/data
references and `.entry label` are resolved in pass two. No macros/includes.

```
.org 0xe000
.entry start
.equ pixel, 0xc000
start: LDI R0, pixel
       LDI R1, 0x21
       STB R1, [R0 + 0]
       HALT
```

`.byte a,b`, `.word a,b` emit lists. `.ascii "text"` supports \n, \r, \t,
\0, \\, and \" escapes. `.fill count[,byte]`, `.align power_of_two`, and
monotonic `.org absolute_address` zero-fill gaps. Instructions must be aligned;
raw data need not be. Default entry is the first instruction; data-only
images require an explicit valid even `.entry`.

Immediates accept -32768…65535; byte values 0…255; memory offsets -32…31.
Branches use absolute labels/addresses, encoded relative to the next word.
The disassembler uses shared ISA metadata and emits `.word` for invalid
encodings, missing immediates, or statically invalid control targets.
