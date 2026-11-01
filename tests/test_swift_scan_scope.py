from pathlib import Path
import runpy
import unittest

needs_swift_scan = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'script/swift_scan_scope.py'))['needs_swift_scan']


class SwiftScanScopeTests(unittest.TestCase):
    def test_only_known_unrelated_changes_can_skip_swift(self):
        self.assertFalse(needs_swift_scan(['README.md', 'docs/ROADMAP.md']))
        self.assertFalse(needs_swift_scan(['studip_sync/session.py', 'tests/test_security.py', 'Pipfile.lock', 'requirements.txt']))
        for path in ['Sources/StudSyncCore/Models.swift', 'Package.swift', 'Package.resolved',
                     'tests/StudSyncCoreTests/ClientTests.swift', '.github/workflows/tests.yml',
                     'script/swift_scan_scope.py', 'docs/generated.swift', 'Sources/config.json', 'new-input']:
            with self.subTest(path=path):
                self.assertTrue(needs_swift_scan(['README.md', path]))
        self.assertTrue(needs_swift_scan([]))
