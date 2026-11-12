"""Pin original v0.3 ROM bytes alongside executable golden/state regressions."""
import hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
fixtures=json.loads((root/'docs/reliability/v0.4-baseline.json').read_text())
demos=root/'zig-out/demos' if (root/'zig-out/demos').exists() else root/'demos'
for name,expected in fixtures['rom_sha256'].items():
 assert hashlib.sha256((demos/name).read_bytes()).hexdigest()==expected,name
print('All five original V1 ROM byte identities match the v0.3 baseline')
