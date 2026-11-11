pub const Fault = error{ InvalidOpcode, Unaligned, ExecuteDenied, AddressOverflow, ReadDenied, WriteDenied, ReservedBits, StackUnderflow, StackOverflow, InvalidStack };
pub const Access = enum { fetch, read, write, stack, decode };
pub const Trap = struct { kind: Fault, pc: u16, address: u16, access: Access, instruction: u16 = 0 };
