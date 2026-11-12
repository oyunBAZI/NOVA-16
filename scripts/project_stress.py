"""Deterministic filesystem project adversaries, seed 0x4e313603."""
import pathlib, random, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
ASM = ROOT/'zig-out/bin/n16asm'
def check(entry, rom, ok):
    p = subprocess.run([str(ASM), str(entry), '--out', str(rom)], capture_output=True, timeout=10)
    assert (p.returncode == 0) == ok, p.stderr
with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    entry, rom = root/'main.asm', root/'program.n16'
    entry.write_text('HALT')
    check(entry,rom,True)
    original = rom.read_bytes()
    # Every depth transition, including depth-limit and cycles.
    for i in range(35):
        (root/f'd{i}.asm').write_text(f'.include "d{i+1}.asm"\n' if i<34 else 'HALT')
    entry.write_text('.include "d0.asm"')
    check(entry,rom,False)
    entry.write_text('.include "empty.asm"\n'*129+'HALT')
    (root/'empty.asm').write_text('')
    check(entry,rom,False)
    entry.write_text(';'+'x'*(1024*1024))
    check(entry,rom,False)
    entry.write_text('\n'*32769+'HALT')
    check(entry,rom,False)
    rng = random.Random(0x4e313603)
    for i in range(100):
        malformed = rng.choice(['.include "../missing.asm"', '.include "main.asm"',
                               '.include "/outside.asm"', '.include "C:/outside.asm"',
                               '.include "unterminated', 'LDI R9, 1', '.equ a, b\n.equ b, a\nHALT'])
        entry.write_text('\n'*rng.randrange(20)+malformed)
        check(entry,rom,False)
        assert rom.read_bytes() == original
    # Explicit symlink traversal regression; CI Linux supplies this gate.
    outside = root.parent/(root.name+'-outside.asm')
    try:
        outside.write_text('HALT')
        (root/'escape.asm').symlink_to(outside)
        entry.write_text('.include "escape.asm"')
        check(entry,rom,False)
    finally:
        outside.unlink(missing_ok=True)
print('Project stress: depth/files/bytes/lines, 100 seeded adversaries and symlink boundary passed')
