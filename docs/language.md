# N16 language revision 1

`n16c` is a Zig compiler targeting the existing ISA V1. It emits ordinary assembly
and uses the same checked assembler/ROM format. There is no second execution VM.

```sh
zig-out/bin/n16c examples/typed/demo.n16c --out zig-out/demo.n16 --assembly zig-out/demo.asm --debug-symbols zig-out/demo.sym2 --layout zig-out/demo-layout.json
zig-out/bin/nova16 run zig-out/demo.n16
zig-out/bin/n16dbg zig-out/demo.n16 --symbols zig-out/demo.sym2
```

Syntax is shown in examples/typed/demo.n16c. Types are u16, i16, bool, [N]scalar
arrays, and named structs with scalar fields. Globals/locals use `var name:type`
with optional scalar initialization; aggregate storage defaults to zero.
`const` requires an initializer and forbids later assignment. Global initializers
must be constant expressions; functions may reference later function declarations.
Functions accept at most four scalar parameters and return one scalar. Every
path must return (a final if/else with both returns qualifies). No aggregate values
or parameters, pointers-as-a-type, heap, strings, floating point or implicit host
calls are supported. Struct fields/arrays are accessed in place. ABI1 specifies
actual word layout and frame/stack/static memory reserves.

Integer operations wrap modulo65536, including signed MIN/-1. Signed division
truncates toward zero and its remainder has the numerator's sign. Shift counts
use their low four bits, matching ISA V1; i16 right shift is arithmetic. No
implicit signed/unsigned conversion between variables is allowed. Numeric
literals may fit an expected scalar type; explicit `u16(x)`, `i16(x)` preserve
bits and `bool(x)` normalizes nonzero to true. `if`/`while` require bool.
Arithmetic/bitwise/comparison precedence is C-like, with short-circuit &&/||
and `condition ? yes : no`. Write parentheses around bit-mask comparisons.

Dynamic bounds failures, zero divisors and recursive frame exhaustion execute
actual guest error-record stores/BRK/HALT; codes at 00F0 are 1/2/3. Constant
out-of-range indices and zero divisors are compile errors. Code cannot silently
overflow the 8 KiB ROM or ABI static/frame reservations.

Device/library intrinsics are explicit: peek8/peek16, poke8/poke16, color,
clear, pixel, rect, glyph, number, bitmap, copy, zero, buttons, frame, wait_frame,
random. Arguments are u16; graphics/memory status routines return status. Raw
peek/poke accesses can produce ordinary CPU permission/alignment traps. These
lower to guest load/store or ABI1 library CALLs, never host drawing or input logic.
Input bit/device semantics are unchanged. Library scratch/register effects are
in guest/README.md. Source maps remain checksum-bound; runtime-generated code is
labelled <n16-runtime>. Compiler layout JSON uses schema 1.

Limits: 1 MiB UTF-8 source, 32,768 tokens, 8,192 AST nodes, AST/parser depth64,
identifier64 bytes, 128 types/functions, 16 scalar struct fields, 1,024 variables,
8192 array elements subject to ABI RAM/frame limits, 1 MiB generated assembly,
16 MiB private compilation arena, 8 KiB ROM. Inputs/output artifacts are validated
and staged before publication. JSON diagnostics opt into schema 1; text includes
file/line/byte-column/error/token. Result owns its source, AST, metadata and ROM;
callers release it once with deinit. Diagnostics borrow the caller's source.

The front end is lexer → bounded AST parser → indexed function and scoped variable
resolution → type/constant checks → direct structured lowering → existing ISA
assembler. Direct lowering is intentional for an 8 KiB target; typed nodes retain
bindings and source spans, so an optimizing IR is not required to deliver real
code or debugging. The next phase independently verifies execution and enriches
variable/source-debugging metadata rather than declaring an interpreter a compiler.

Compiler maps use schema 3 (ROM checksum, existing symbols/source spans plus
variable records). Ordinary assembly still emits schema 2, and legacy maps load
unchanged. `vars` and `var NAME` inspect initialized globals and in-scope frame
slots without acknowledging MMIO; arrays/structs show up to 16 words. Values are
available in the current function, not suspended callers. Local ranges begin
after initialization and end at the lexical block exit. Compiler runtime errors
store code at 00F0 and original source line at 00F2 before BRK; debugger status
reports the original file/line. Device intrinsics can produce architectural traps
and retain their original source spans. Statement `next`, instruction trace,
snapshots and reverse work on compiled ROMs.

`src/compiler/reference.zig` is a bounded pure-AST correctness oracle, excluded
from application execution. It independently computes arithmetic with wide
integers, global/frame layout and control flow. The seeded differential campaign
executes the generated ROM on the unchanged V1 CPU and compares results. It is
not a second application runtime and does not interpret device intrinsics.

Source `next` skips `<n16-runtime>` implementation spans while keeping explicit
breakpoints, traps and the instruction budget effective. It may enter other
user functions at their mapped source locations; it is statement stepping, not
a promise to skip all user calls. Instruction `step`/trace still expose library
instructions. This distinction is verified on a real clear() call.

## Reachable code and size reports

The compiler retains typed functions reachable from `main`, including forward
calls and recursive cycles. It still validates every declared function: an
unused function with an invalid body remains a compilation error. There are no
function pointers or indirect typed calls in language revision 1. Calls in both
arms of a conditional are conservatively retained; this is not constant folding.

The ABI1 library is linked from the same sources used by assembly developers.
An assembler-parser-based graph retains exact operand symbol references,
transitive CALL/branch dependencies, fallthrough, shared return tails and
address-taken font data. Original block order is preserved. This linker is
restricted to the reviewed position-independent library, not arbitrary assembly
projects: indirect library control flow and unsupported layout directives fail
explicitly. No runtime instructions are rewritten. Hand-authored assembly and
its default full-library inclusion are unchanged.

```sh
zig-out/bin/n16c examples/projects/crates/main.n16c --out zig-out/crates.n16 --size-report zig-out/crates-size.json
```

`--size-report PATH` writes deterministic schema-1 JSON containing payload bytes,
8,192-byte capacity/percentage, static RAM bytes, the ABI's 256-byte local frame,
retained typed functions and library blocks with their byte contributions,
removed function/block counts, and compiler scaffold bytes. Library entries are
label blocks (including internal shared tails and data), not standalone public
functions. Contributions plus scaffold bytes sum to the actual payload. Timing
is deliberately separate so reports remain byte-reproducible. Return-address
stack consumption remains governed by ABI1; `frame_bytes` is not a measured
maximum recursion depth. Existing `--layout` and map schemas are unchanged.

Only retained functions have ROM locations and local-variable debug records.
Global variable layout is preserved. New compiler output has new ROM checksums;
regenerate its checksum-bound map/snapshot artifacts together. Existing ROMs,
legacy maps, V1 hardware and V2 hardware contracts are unchanged.
