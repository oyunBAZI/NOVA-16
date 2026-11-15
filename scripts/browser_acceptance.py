"""Real Chromium acceptance for native and offline Workbench (development only).

Install scripts/browser-requirements.txt and `python -m playwright install chromium`.
No browser/test dependency is needed to use NOVA-16 itself. A launch failure is
an explicit test failure, never an automatic skip or a claimed visual pass.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def exercise(browser, url, mode, destination):
    context = browser.new_context(viewport={'width': 1280, 'height': 900}, accept_downloads=True)
    page = context.new_page()
    errors, violations, network = [], [], []
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('dialog', lambda dialog: dialog.accept())
    page.on('request', lambda request: network.append(request.url))
    page.expose_function('novaTestViolation', lambda value: violations.append(value))
    page.add_init_script("""document.addEventListener('securitypolicyviolation', event => {
      window.novaTestViolation({directive:event.violatedDirective,blocked:event.blockedURI});
    });""")
    started = time.monotonic()
    def wait(expression):
        # wait_for_function evaluates its predicate inside the page and is
        # rejected by the runtime CSP. Poll through the debugger protocol;
        # never weaken CSP or use a bypass_csp browser context for acceptance.
        deadline = time.monotonic() + 30
        while not page.evaluate(expression):
            if time.monotonic() >= deadline:
                raise AssertionError('Browser state did not arrive: ' + expression)
            page.wait_for_timeout(50)
    try:
        page.goto(url, wait_until='load')
        wait("document.getElementById('connection').textContent.startsWith('CONNECTED')")
        assert page.locator('#demos option').count() == 11
        assert page.evaluate('current.profile') == 1
        assert page.evaluate('sound===null'), 'Boot must not request audio automatically'
        geometry = page.evaluate("""() => {
          const source=document.getElementById('source').getBoundingClientRect();
          const overlay=document.getElementById('syntax').getBoundingClientRect();
          return {source:source.width,overlay:overlay.width,left:source.left-overlay.left,align:getComputedStyle(document.getElementById('syntax')).textAlign};
        }""")
        assert abs(geometry['source'] - geometry['overlay']) <= 2, geometry
        assert abs(geometry['left']) <= 2 and geometry['overlay'] > 200, geometry
        assert geometry['align'] != 'right', geometry

        program = 'fn main()->u16 {\n var value:u16=41;\n return value+1;\n}'
        page.locator('#source').fill(program)
        page.locator('#build').click()
        wait("document.getElementById('source-status').textContent==='BUILD SUCCEEDED'")
        checksum = page.evaluate('current.state.rom_checksum')
        page.locator('#command').fill('continue')
        page.locator('#command-form button').click()
        wait('current.state.halted')
        assert page.evaluate('current.state.registers[0]') == 42
        assert page.locator('#machine-status').inner_text() == 'HALT'
        page.locator('#source').fill(program + '\n')
        assert page.evaluate('sourceMatches') is False
        assert 'compiled ROM' in page.locator('#source-location').inner_text()
        page.locator('#source').fill(program)
        assert page.evaluate('sourceMatches') is True

        with page.expect_download() as download:
            page.locator('#save-snapshot').click()
        snapshot = destination / f'{mode}.n16s'
        download.value.save_as(snapshot)
        assert snapshot.read_bytes().startswith(b'N16S')
        page.locator('#snapshot-file').set_input_files({'name': 'corrupt.n16s', 'mimeType': 'application/octet-stream', 'buffer': b'broken'})
        wait("document.getElementById('console').textContent.includes('Snapshot')")
        assert page.evaluate('current.state.registers[0]') == 42
        assert page.evaluate('current.state.rom_checksum') == checksum

        page.locator('#source').fill('fn main()->u16{return missing;}')
        page.locator('#build').click()
        wait("document.getElementById('source-status').textContent==='BUILD FAILED'")
        assert 'UndefinedVariable' in page.locator('#diagnostics').inner_text()
        assert page.evaluate('current.state.rom_checksum') == checksum
        assert page.evaluate('current.state.registers[0]') == 42
        assert page.locator('#build').is_enabled()

        page.locator('#source').fill(program)
        page.locator('#build-architecture').select_option('nova16-v2')
        wait("document.getElementById('draft-status').textContent.startsWith('Draft saved')")
        page.reload(wait_until='load')
        wait('editorReady')
        assert page.locator('#source').input_value() == program
        assert page.locator('#build-architecture').input_value() == 'nova16-v2'
        assert 'DRAFT RECOVERED' in page.locator('#source-status').inner_text()

        imported = b'fn main()->u16{return 99;}'
        page.locator('#source-file').set_input_files({'name': 'main.n16c', 'mimeType': 'text/plain', 'buffer': imported})
        wait("document.getElementById('source').value.includes('99')")
        page.locator('#rom-file').set_input_files(str(ROOT / 'zig-out/demos/nova_sound.n16'))
        wait("current.title==='Imported ROM'")
        assert page.evaluate('current.profile') == 2
        assert page.locator('#source').input_value() == imported.decode()
        page.locator('#demos').select_option('paint')
        page.locator('#load').click()
        wait("current.title==='Paint'")
        page.locator('#screen').focus()
        page.keyboard.down('z')
        wait('current.input_held===16')
        page.keyboard.up('z')
        wait('current.input_held===0')
        page.locator('#reverse').click()
        wait('current.input_held===16')
        assert page.locator('[data-bit="16"]').get_attribute('aria-pressed') == 'true'
        # Reverse deliberately restores the historical device state. Refocus
        # the controller before testing its focus-loss release contract.
        page.locator('#screen').focus()
        page.locator('#source').focus()
        wait('current.input_held===0')
        page.locator('#frame').click()
        wait('current.state.frame_count>0')
        assert page.evaluate("""() => {
          const bytes=document.getElementById('screen').getContext('2d').getImageData(0,0,128,96).data;
          for(let i=0;i<128*96;i++) {
            const value=parseInt(current.vram.slice((i>>1)*2,(i>>1)*2+2),16);
            const color=current.display_enabled?(value>>((i&1)*4))&15:0;
            for(let channel=0;channel<3;channel++)if(bytes[i*4+channel]!==current.palette[color*3+channel])return false;
            if(bytes[i*4+3]!==255)return false;
          }
          return true;
        }"""), 'Canvas must display exact guest pixels'

        page.locator('#source').fill('// scroll\n' * 150 + 'fn main()->u16{return 1;}')
        page.evaluate("""() => {
          const source=document.getElementById('source');source.scrollTop=600;source.dispatchEvent(new Event('scroll'));
        }""")
        assert page.evaluate("document.getElementById('source').scrollTop===document.getElementById('syntax').scrollTop")
        page.screenshot(path=str(destination / f'{mode}-desktop.png'), full_page=True)
        page.set_viewport_size({'width': 390, 'height': 844})
        assert page.evaluate('document.documentElement.scrollWidth<=window.innerWidth'), 'Mobile layout must not overflow horizontally'
        page.screenshot(path=str(destination / f'{mode}-mobile.png'), full_page=True)
        page.set_viewport_size({'width': 1280, 'height': 900})

        page.locator('#demos').select_option('nova_sound')
        page.locator('#load').click()
        wait('current.profile===2')
        page.locator('#audio-tab').click()
        page.locator('#listen').click()
        wait("sound?.state==='running'")
        page.locator('#run').click()
        wait('current.state.frame_count>=2')
        page.locator('#run').click()
        wait('running===false')
        assert page.locator('#run').get_attribute('aria-pressed') == 'false'
        assert page.locator('#machine-status').inner_text() != 'RUNNING'
        assert page.evaluate('current.audio.pcm.length') == 800
        with page.expect_download() as download:
            page.locator('#wav').click()
        wav = destination / f'{mode}.wav'
        download.value.save_as(wav)
        assert wav.read_bytes().startswith(b'RIFF') and wav.stat().st_size == 1644
        page.locator('#listen').click()
        wait('sound===null')
        assert not errors, errors
        assert not violations, violations
        if mode == 'offline':
            assert not [url for url in network if url.startswith(('http:', 'https:'))], network
        return {'mode': mode, 'passed': True, 'seconds': round(time.monotonic() - started, 3),
                'viewport_geometry': geometry, 'page_errors': errors, 'csp_violations': violations,
                'audio': 'real AudioContext running and guest WAV bytes; no listening claim'}
    except Exception:
        page.screenshot(path=str(destination / f'{mode}-failure.png'), full_page=True)
        raise
    finally:
        context.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', help='Optional existing Chromium executable')
    parser.add_argument('--out', type=Path, default=ROOT / 'zig-out/browser')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    from playwright.sync_api import sync_playwright
    report = {'schema_version': 1, 'checks': [], 'passed': False}
    process = None
    try:
        with sync_playwright() as playwright:
            options = {'headless': True}
            if args.executable:
                options['executable_path'] = args.executable
            browser = playwright.chromium.launch(**options)
            try:
                process = subprocess.Popen([sys.executable, '-u', str(ROOT / 'scripts/workbench.py'), '--no-browser'],
                                           cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                line = process.stdout.readline().strip()
                if not line.startswith('NOVA Workbench: http://127.0.0.1:'):
                    raise RuntimeError('Native Workbench did not announce a local session')
                report['checks'].append(exercise(browser, line.removeprefix('NOVA Workbench: '), 'native', args.out))
                offline = ROOT / 'zig-out/web/NOVA16-Offline-Workbench.html'
                report['checks'].append(exercise(browser, offline.as_uri(), 'offline', args.out))
                report['passed'] = True
            finally:
                browser.close()
    except Exception as error:
        report['failure'] = str(error)
        raise
    finally:
        if process:
            process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=5)
        (args.out / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
