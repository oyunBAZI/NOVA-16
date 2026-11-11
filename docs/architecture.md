# Architecture
NOVA-16 ISA V1 uses eight 16-bit registers, separate PC/SP, and Z/N/C/V flags.
Words are little-endian; instructions and word accesses are even-aligned.
Reset sets registers and flags to zero, SP=BFFE, and PC=E000+ROM entry.

| Range | Role | Permissions |
|---|---|---|
|0000–BFFF|RAM, stack|RWX|
|C000–D7FF|128×96 packed 4bpp framebuffer|RW|
|D800–DFFF|Whitelisted MMIO|Per register|
|E000–FFFF|8 KiB ROM|RX|

CPU, bus and devices have no host I/O. Host applications own file handling,
input injection, pacing and presentation. One frame retires at most 20,000
instructions. The full normative contract is in specification.md.
