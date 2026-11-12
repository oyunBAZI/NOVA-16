# Manually inspectable ISA vectors
Bytes below are little-endian W0 followed by W1 where present. PC starts E000,
SP BFFE and unspecified registers/flags are zero. Flags are numeric Z=1,N=2,C=4,V=8.
All rows retire one instruction except traps. These cases are also covered by
CPU/conformance tests using independent arithmetic references.

| Bytes | Initial state | Expected state |
|---|---|---|
|00 00|reset|PC=E002, unchanged flags|
|01 00|reset|HALT, PC=E002|
|02 00|reset|BRK pause, PC=E002; resume starts at E002|
|00 22 34 12|reset|R1=1234, PC=E004|
|40 30|R0=FFFF,R1=1|R0=0, flags=5|
|40 30|R0=7FFF,R1=1|R0=8000, flags=10|
|40 40|R0=0,R1=1|R0=FFFF, flags=2|
|40 40|R0=8000,R1=1|R0=7FFF, flags=12|
|40 80|R0=1,R1=1|R0 unchanged, flags=5|
|04 F0|R0=8001,R1=0,C=1,V=1|R0=8001, flags=6|
|04 F2|R0=8001,R1=15|R0=FFFF, flags=2|
|01 D1|Z=1|PC=E004 (word-scaled branch)|
|00 E1 00 01|reset|PC=0100, SP=BFFC, [BFFC]=E004|
|00 F8|R0=1234|SP=BFFC, RAM[BFFC..BFFD]=34 12|
|00 F9|empty stack|StackUnderflow, PC=E000, no retirement|
|3F B0|R0=0|AddressOverflow reading -1, PC=E000|
|01 10|reset|InvalidOpcode (reserved bit), PC=E000|
|00 A0|R0=E000|WriteDenied, PC=E000|

Exhaustive masks check all 65,536 first words; round trips cover every valid
encoding. Execution tests cover all ALU register pairs and boundary operands,
all condition/flag combinations, stack limits, checked memory and MMIO transactions.
