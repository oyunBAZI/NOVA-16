# N16R version 1
All multibyte integers are little-endian. The file must be exactly 32+length bytes.

| Offset | Size | Value |
|---|---:|---|
|0|4|ASCII N16R|
|4|2|Version 1|
|6|2|Even entry offset, less than payload length|
|8|2|Payload length 1–8192|
|10|2|Flags zero|
|12|4|IEEE CRC-32 of payload|
|16|16|Reserved zero|
|32|length|ROM bytes mapped at E000|

Unused ROM bytes are zero. Loading validates all fields before changing machine
state. Errors are stable names: TruncatedHeader, BadMagic, BadVersion, BadLength,
BadSize, BadFlags, BadReserved, BadEntry, BadChecksum. Checksum uses IEEE CRC-32
(the same standard as Python zlib.crc32). No compression, external resources,
executables, network access, or host extensions are embedded in the format.
