# V1 decisions and ambiguities

1. **LDI reserved bits**: source bits [8:6] have no operand meaning; all nine
   low bits of W0 must be zero. Immediate extended operations likewise reserve Rs.
   The exhaustive decoder mask test enforces this.
2. **Sequential PC overflow**: decoding an instruction whose next PC would be
   65536 traps AddressOverflow before retirement. PC does not silently wrap.
   This applies even to HALT/JMP at the final word. A 4-byte instruction must
   fetch both words from executable memory. Branch targets are checked only
   when taken. Regression tests exercise end-of-space and execute-region faults.
3. **Stack ownership**: SP/depth invariant is BFFE - 2×depth. The guest has no
   instruction that writes SP; host/debug API corruption traps InvalidStack.
   RET validates its target before consuming the word. POPF masks reserved bits.
4. **MMIO word transactions**: both bytes must be whitelisted for the requested
   access before any side effect occurs. KEY_HELD/KEY_PRESSED and FRAME_LO/HI
   can be read as words. Word writes starting D804 fail because D805 is read-only.
   Debugger inspection uses peek and never acknowledges read-clear registers.
5. **Frame stop**: an invoked frame increments FRAME and sets VBLANK once even
   when a stop occurs early. Runners do not invoke subsequent guest frames after
   HALT/BRK/trap. GUI can keep presenting the last image without advancing time.
6. **Assembler constants**: `.equ name, expression`. Forward labels and constant
   chains resolve after layout; cyclic/undefined chains reject. Layout directives
   need already resolvable sizes/addresses, preventing unstable multi-pass layout.
   `.align` uses positive powers of two. `.fill count[,byte]` defaults to zero.
   Negative 16-bit data/immediates accept -32768…-1 as two's-complement.
7. **Execution limits**: headless default 120 guest frames, GUI default 120
   presentations, overall default 10 million instructions. Budgets stop cleanly
   without pretending HALT occurred. Explicit larger budgets are available.
8. **Input schedules**: ordered lines `zero_based_host_frame mask`; mask persists.
   Duplicate/out-of-order frames reject. Schedules are headless-only; GUI uses
   physical keys. GUI controls are Space (pause), R (reset), Escape (quit).
9. **Unknown disassembly**: malformed words or unencodable static targets are
   emitted as `.word`, preserving bytes rather than inventing valid instructions.
   For an incomplete final immediate, the first word alone is preserved.
10. **Code size**: the specification explicitly calls 10–12k LOC a scope estimate,
    not a quota. Shared ISA tables, bounded data structures and compact modules
    reduce the required implementation. No source duplication or padding is added.

11. **Demand-linked typed programs (2026-11-12)**: compiler-generated ROM layout
    may change while ISA/ABI/N16R/N16S semantics remain fixed. Retain typed call
    reachability from main; validate unused bodies before suppressing emission.
    Link the reviewed ABI1 library through parsed exact symbol/control-flow/data
    references and fallthrough, keeping original block order. Reject unsupported
    indirect library flow/layout rather than guessing. Keep original assembly
    sources and full-library callers unchanged. Rebuild maps for new checksums;
    omit debug locals belonging to removed functions. Preserve all original V1
    ROM hashes and application framebuffer/state replays. This decision does not
    approve new hardware or Profile-2 contract changes.
