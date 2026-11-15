"""Failure-path tests for validation reporting; commands are deliberately simulated."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


class DriverAcceptance(unittest.TestCase):
    def simulate(self, failure=None):
        original_run, original_which = subprocess.run, shutil.which
        count = 0
        with tempfile.TemporaryDirectory(prefix='nova16-validator-') as directory:
            report = Path(directory) / 'report.json'
            # Creating a source after the initial digest simulates concurrent
            # editing without touching an existing user/repository source file.
            probe = ROOT / 'scripts' / ('validation_probe_' + Path(directory).name + '.py')

            def command(args, *positional, **kwargs):
                nonlocal count
                if str(args[0]) == 'git':
                    return original_run(args, *positional, **kwargs)
                count += 1
                if count == 2:
                    if failure == 'timeout':
                        raise subprocess.TimeoutExpired(args, 600, output=b'partial stdout', stderr=b'partial stderr')
                    if failure == 'exit':
                        return subprocess.CompletedProcess(args, 7, stdout='failed gate', stderr='test error')
                    if failure == 'changed':
                        probe.write_text('# concurrent source change\n', encoding='utf-8')
                return subprocess.CompletedProcess(args, 0, stdout='simulated command success', stderr='')

            def which(name):
                return str(Path(directory) / 'simulated-zig') if name == 'simulated-zig' else original_which(name)

            outcome = 0
            try:
                with mock.patch.object(sys, 'argv', ['validate.py', '--zig', 'simulated-zig', '--mode', 'ReleaseSafe', '--out', str(report)]), \
                     mock.patch.object(subprocess, 'run', side_effect=command), \
                     mock.patch.object(shutil, 'which', side_effect=which), contextlib.redirect_stdout(io.StringIO()):
                    try:
                        runpy.run_path(str(ROOT / 'scripts/validate.py'), run_name='__main__')
                    except SystemExit as error:
                        outcome = error.code
                self.assertTrue(report.is_file(), 'Every executed gate must leave reviewable evidence')
                self.assertFalse(report.with_name(report.name + '.tmp').exists())
                return outcome, json.loads(report.read_text(encoding='utf-8'))
            finally:
                probe.unlink(missing_ok=True)

    def test_success_reports_an_unchanged_source_tree(self):
        status, report = self.simulate()
        self.assertEqual(status, 0)
        self.assertTrue(report['passed'])
        self.assertFalse(report['source_changed_during_validation'])
        self.assertTrue(all(check['status'] == 'passed' for check in report['checks']))

    def test_failed_command_stops_and_preserves_its_output(self):
        status, report = self.simulate('exit')
        self.assertEqual(status, 7)
        self.assertFalse(report['passed'])
        self.assertEqual(len(report['checks']), 2)
        self.assertEqual(report['checks'][-1]['status'], 'failed')
        self.assertIn('failed gatetest error', report['checks'][-1]['output'])

    def test_timeout_is_a_recorded_failure_not_an_unfinished_pass(self):
        status, report = self.simulate('timeout')
        self.assertEqual(status, 124)
        self.assertFalse(report['passed'])
        self.assertTrue(report['checks'][-1]['timed_out'])
        self.assertEqual(report['checks'][-1]['output'], 'partial stdoutpartial stderr')

    def test_concurrent_source_changes_invalidate_passing_commands(self):
        status, report = self.simulate('changed')
        self.assertIn('Source changed', str(status))
        self.assertFalse(report['passed'])
        self.assertTrue(report['source_changed_during_validation'])
        self.assertTrue(all(check['exit_code'] == 0 for check in report['checks']))


if __name__ == '__main__':
    unittest.main(verbosity=2)
