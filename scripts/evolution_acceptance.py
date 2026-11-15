"""V2 applications, deep rewind and typed build targets on real native tools."""
import hashlib
import json
import pathlib
import struct
import subprocess
import tempfile
import unittest

import workbench as w

ROOT=pathlib.Path(__file__).resolve().parents[1]
SCENES=json.loads((ROOT/'docs/evolution/scenes.json').read_text())

def execute(name,*args,stdin=None):
    p=subprocess.run([w.executable(name),*map(str,args)],input=stdin,capture_output=True,text=True,timeout=120)
    assert p.returncode==0,(p.args,p.stdout[-2000:],p.stderr[-2000:])
    return p.stdout

class EvolutionAcceptance(unittest.TestCase):
    def test_ten_application_scenes_and_native_replay_pcm_parity(self):
        with tempfile.TemporaryDirectory() as directory:
            directory=pathlib.Path(directory)
            for key,case in SCENES.items():
                app,scene=key.split('-',1)
                with self.subTest(scene=key):
                    rom=w.DEMOS/(app+'.n16')
                    mapping=json.loads((w.DEMOS/(app+'.map.json')).read_text())
                    ppm,wav=directory/'screen.ppm',directory/'audio.wav'
                    args=['run',rom,'--frames',case['frames'],'--max-instructions',case['frames']*20000+20000,'--screenshot',ppm,'--wav',wav]
                    events={}
                    if case['input']:
                        schedule=ROOT/'examples/projects'/app/(case['input']+'.input')
                        args+=['--input',schedule]
                        events={int(f):int(v) for f,v in (line.split() for line in schedule.read_text().splitlines())}
                    native=json.loads(execute('nova16',*args))
                    self.assertFalse(native['trapped']);self.assertFalse(native['halted'])
                    self.assertEqual(hashlib.sha256(ppm.read_bytes()).hexdigest(),case['sha256'])
                    pcm=struct.unpack('<'+str((wav.stat().st_size-44)//2)+'h',wav.read_bytes()[44:])
                    self.assertEqual(any(pcm),case['audible'])
                    self.assertEqual(any(pcm[-800:]),case['last_frame_audible'])
                    bridge=w.Bridge(rom)
                    try:
                        bridge.request({'op':'command','command':'history 0'})
                        for frame in range(case['frames']):
                            if frame in events:
                                bridge.request({'op':'command','command':f'input {events[frame]}'})
                            result=bridge.request({'op':'replay_frame','address':256})
                            self.assertTrue(result['ok'])
                        self.assertEqual(result['state'],native)
                        self.assertEqual(result['audio']['pcm'],list(pcm[-800:]))
                        snapshot=bytes.fromhex(bridge.request({'op':'snapshot'})['snapshot'])
                    finally:bridge.close()
                    ram=snapshot[272:272+65536]
                    variables={v['name']:v for v in mapping['variables'] if not v['frame_relative']}
                    for name,value in case['values'].items():
                        v=variables[name];actual=int.from_bytes(ram[v['address']:v['address']+2],'little')
                        self.assertEqual(actual,value,(key,name))
                    if app=='nova_tracker' and scene in ('edited','resumed'):
                        for name,index,value in [('notes',0,2),('notes',1,1),('waves',1,1)]:
                            offset=variables[name]['address']+index*2
                            self.assertEqual(int.from_bytes(ram[offset:offset+2],'little'),value)

    def test_deep_frame_undo_and_reexecution_beyond_old_limit(self):
        bridge=w.Bridge(w.DEMOS/'nova_tracker.n16')
        try:
            for _ in range(30):bridge.request({'op':'frame'})
            first=bridge.request({'op':'snapshot'})['snapshot']
            for _ in range(60):bridge.request({'op':'frame'})
            later=bridge.request({'op':'snapshot'})['snapshot']
            self.assertGreaterEqual(bridge.request({})['history_count'],60)
            for _ in range(60):
                self.assertTrue(bridge.request({'op':'command','command':'reverse'})['ok'])
            self.assertEqual(bridge.request({'op':'snapshot'})['snapshot'],first)
            for _ in range(60):bridge.request({'op':'frame'})
            self.assertEqual(bridge.request({'op':'snapshot'})['snapshot'],later)
        finally:bridge.close()

    def test_typed_v2_project_and_editor_target_failures_are_atomic(self):
        model=w.Workbench()
        try:
            bootstrap=model.dispatch({'op':'bootstrap'})[1]
            self.assertIsInstance(bootstrap['editor_source'],str)
            self.assertNotIsInstance(bootstrap['source'],str)
            def dispatch(**data):
                status,result=model.dispatch(dict(data,revision=model.revision));self.assertEqual(status,200);return result
            source=dispatch(op='edit_demo',demo='nova_tracker')
            self.assertEqual(source['editor_architecture'],'nova16-v2')
            built=dispatch(op='build',source=source['editor_source'],architecture='nova16-v2',optimization='size')
            self.assertEqual(built['profile'],2)
            before=dispatch(op='vm',request={'op':'snapshot'})['snapshot']
            for fields in ({'architecture':'bad'},{'optimization':'bad'}):
                with self.assertRaises(ValueError):dispatch(op='build',source='fn main()->u16{return 0;}',**fields)
                self.assertEqual(dispatch(op='vm',request={'op':'snapshot'})['snapshot'],before)
            with self.assertRaises(ValueError):dispatch(op='edit_demo',demo='../secret')
        finally:model.close()

if __name__=='__main__':unittest.main(verbosity=2)
