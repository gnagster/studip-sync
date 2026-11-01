import importlib
import json
import os
from pathlib import Path
import pickle
import stat
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

from studip_sync import parsers
from studip_sync.helpers import JSONConfig

with patch.dict(sys.modules, {
    'studip_sync.config': SimpleNamespace(CONFIG=SimpleNamespace()),
    'studip_sync.plugins.plugins': SimpleNamespace(PLUGINS=MagicMock()),
}):
    from studip_sync.studip_rsync import CourseRSync, check_and_cleanup_form_data


class PathSecurityTests(unittest.TestCase):
    def test_folder_names_are_checked_after_normalization(self):
        for use_api in (False, True):
            for name in ('', '.', '..', '\uff0e\uff0e', '\ufe52\ufe52', '.\uff0e'):
                with self.subTest(use_api=use_api, name=name):
                    with self.assertRaises(parsers.ParserError):
                        check_and_cleanup_form_data([], [{'id': 'aa', 'name': name}], use_api)
            _, folders = check_and_cleanup_form_data(
                [], [{'id': 'aa', 'name': 'Über / notes'}], use_api)
            self.assertEqual(folders, [{'id': 'aa', 'name': 'Über -- notes'}])

    def test_recursive_sync_rejects_escape_before_download(self):
        with tempfile.TemporaryDirectory() as directory:
            server = MagicMock()
            server.get_files_index_from_api.side_effect = [
                ([], [{'id': 'aa', 'name': '\uff0e\uff0e'}]), ([], []),
            ]
            sync = CourseRSync(server, directory, directory, {
                'course_id': 'bb', 'save_as': 'Course'}, True, True)
            with self.assertRaises(parsers.ParserError):
                sync.download_recursive()
            server.download_file_api.assert_not_called()
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_legitimate_nested_download_still_works(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory) / 'work'
            work.mkdir()
            root = Path(directory) / 'destination'
            server = MagicMock()
            server.get_files_index_from_api.side_effect = [
                ([], [{'id': 'aa', 'name': 'Über / notes'}]),
                ([{'id': 'bb', 'name': 'lecture.txt', 'size': 5, 'chdate': 1}], []),
            ]
            server.download_file_api.side_effect = lambda _, path: Path(path).write_bytes(b'notes')
            sync = CourseRSync(server, str(work), str(root), {
                'course_id': 'cc', 'save_as': 'Course'}, True, True)
            sync.download_recursive()
            target = root / 'Über -- notes' / 'lecture.txt'
            self.assertEqual(target.read_bytes(), b'notes')
            server.plugins.hook.assert_called_once_with(
                'hook_file_download_successful', 'lecture.txt', 'Course', str(target))

    def test_course_components_in_both_bootstrap_formats(self):
        for name in ('', '  ', '.', '..', '  ..  '):
            for modern in (False, True):
                with self.subTest(name=name, modern=modern):
                    with self.assertRaises(parsers.ParserError):
                        list(parsers.extract_courses(self.course_html(name, modern), False))
        for modern in (False, True):
            for name, expected in [('Über / course', 'Über -- course'),
                                   (' ../ ', '..--'), ('Ｆｕｌｌｗｉｄｔｈ', 'Ｆｕｌｌｗｉｄｔｈ')]:
                courses = list(parsers.extract_courses(self.course_html(name, modern), False))
                self.assertEqual(courses[0]['save_as'], expected)

    @staticmethod
    def course_html(name, modern):
        groups = [{'name': 'Semester', 'data': [{'ids': ['aa']}]}]
        courses = {'aa': {'name': name}}
        if modern:
            data = {'appPath': 'my-courses/MyCourses', 'vuexStoreData': {
                'mycourses': {'setGroups': groups, 'setCourses': courses}}}
            return '<div data-vue-app><script type="application/json">' + json.dumps(data) + '</script></div>'
        return '<script>MyCoursesData = ' + json.dumps({'groups': groups, 'courses': courses}) + ';</script>'


class CredentialSecurityTests(unittest.TestCase):
    def test_config_creation_rewrite_and_read_are_private(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'config' / 'config.json'
            old_umask = os.umask(0o022)
            try:
                for existing in (False, True):
                    if existing:
                        target.chmod(0o644)
                    JSONConfig.save_config(str(target), {'user': {'password': 'test-only'}})
                    self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
                    self.assertEqual(json.loads(target.read_text()), {'user': {'password': 'test-only'}})
                target.chmod(0o644)
                self.assertEqual(JSONConfig(str(target)).config['user']['password'], 'test-only')
                self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            finally:
                os.umask(old_umask)

    def test_private_file_restricts_access_before_writing(self):
        from studip_sync.helpers import open_private_file
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'token.pickle'
            target.write_bytes(b'old')
            target.chmod(0o644)
            with patch('studip_sync.helpers.os.fchmod', side_effect=PermissionError('test')):
                with self.assertRaises(PermissionError):
                    with open_private_file(target, 'wb'):
                        self.fail('Permission failure must prevent access')
            self.assertEqual(target.read_bytes(), b'old')
            with open_private_file(target, 'wb') as token:
                self.assertEqual(stat.S_IMODE(os.fstat(token.fileno()).st_mode), 0o600)
                pickle.dump({'token': 'test-only'}, token)
            with target.open('rb') as token:
                self.assertEqual(pickle.load(token), {'token': 'test-only'})

    def test_private_file_removes_macos_acl_read_grants(self):
        from studip_sync.helpers import open_private_file
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'config.json'
            for mode in ('r', 'w'):
                target.write_text('test-only')
                subprocess.run(['/bin/chmod', '+a', 'everyone allow read', str(target)], check=True)
                before = subprocess.check_output(['/bin/ls', '-le', str(target)], text=True)
                self.assertGreater(len(before.splitlines()), 1)
                with open_private_file(target, mode):
                    after = subprocess.check_output(['/bin/ls', '-le', str(target)], text=True)
                    self.assertEqual(len(after.splitlines()), 1)
                    self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)

    def test_google_token_creation_and_existing_loads_are_private(self):
        plugin_module = importlib.import_module('studip_sync.plugins.google-tasks')
        with tempfile.TemporaryDirectory() as directory:
            plugin = plugin_module.Plugin(directory)
            target = Path(plugin.token_pickle_path)
            credentials = SimpleNamespace(valid=True)
            service = MagicMock()
            service.tasklists.return_value.list.return_value.execute.return_value = {
                'items': [{'id': 'list', 'title': 'Test'}]}
            Path(plugin.credentials_path).parent.mkdir()
            Path(plugin.credentials_path).write_text('{}')
            flow = MagicMock()
            flow.run_local_server.return_value = credentials
            old_umask = os.umask(0o022)
            try:
                with patch.object(plugin_module.InstalledAppFlow, 'from_client_secrets_file', return_value=flow), \
                        patch.object(plugin_module, 'build', return_value=service), \
                        patch('builtins.input', return_value='list'):
                    plugin.hook_configure()
                    self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
                    target.chmod(0o644)
                    plugin.hook_configure()
                    self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
                    target.chmod(0o644)
                    plugin.hook_start()
                    self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
                    flow.run_local_server.assert_called_once_with(port=0)
                    self.assertTrue(plugin_module.build.call_args.kwargs['credentials'].valid)
            finally:
                os.umask(old_umask)


if __name__ == '__main__':
    unittest.main()
