import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from sync_upstream import merge_json, render_readme, sync


class SyncTest(unittest.TestCase):
    def test_translation_changes_merge_by_key_and_reject_same_key_conflicts(self):
        self.assertEqual(merge_json({'zh': {'old': 'x'}},
                                    {'zh': {'old': 'x', 'fork': 'f'}},
                                    {'zh': {'old': 'y', 'new': 'n'}}),
                         {'zh': {'old': 'y', 'new': 'n', 'fork': 'f'}})
        self.assertEqual(merge_json({'a': 1}, {}, {'a': 1}), {})
        with self.assertRaises(ValueError):
            merge_json({'a': 1}, {'a': 2}, {'a': 3})

    def test_readme_retains_upstream_body_and_fork_section(self):
        rendered = render_readme('<div><h1>VeneraX</h1></div>\nNew upstream guide', 'Fork section')
        self.assertIn('Personal iOS Fork', rendered)
        self.assertIn('Fork section\n\nNew upstream guide', rendered)

    def exercise_merge(self, code_conflict=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)

            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root).decode().strip()

            def write(path, content):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content, encoding='utf-8')

            def commit(message):
                git('add', '-A')
                git('commit', '-qm', message)
                return git('rev-parse', 'HEAD')

            git('init', '-q')
            git('config', 'user.name', 'Test')
            git('config', 'user.email', 'test@example.com')
            git('config', 'commit.gpgsign', 'false')
            for language, name in [('zh', 'README.md'), ('en', 'README_EN.md')]:
                write(name, '<div><h1>VeneraX</h1></div>\nOriginal guide')
                write(f'.github/fork/readme.{language}.md', 'Fork section')
            write('assets/translation.json', json.dumps({'zh': {'base': 'old'}}))
            write('.github/workflows/ci.yml', 'original')
            write('lib/main.dart', 'base')
            base = commit('base')
            write('README.md', '<div><h1>VeneraX</h1></div>\nUpstream guide')
            write('README_EN.md', '<div><h1>VeneraX</h1></div>\nUpstream guide')
            write('assets/translation.json', json.dumps({'zh': {'base': 'new'}}))
            write('.github/workflows/ci.yml', 'upstream')
            write('lib/main.dart', 'upstream')
            upstream = commit('upstream')
            git('checkout', '-q', '-b', 'fork', base)
            write('README.md', '<div><h1>VeneraX</h1></div>\nPersonal fork guide')
            write('README_EN.md', '<div><h1>VeneraX</h1></div>\nPersonal fork guide')
            write('assets/translation.json', json.dumps({'zh': {'base': 'old', 'fork': 'notice'}}))
            write('.github/workflows/ci.yml', 'fork')
            if code_conflict:
                write('lib/main.dart', 'fork code')
            before = commit('fork')
            previous = Path.cwd()
            try:
                os.chdir(root)
                with patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': ''}):
                    if code_conflict:
                        with self.assertRaisesRegex(RuntimeError, 'lib/main.dart'):
                            sync(upstream)
                        self.assertEqual(git('rev-parse', 'HEAD'), before)
                        self.assertEqual(git('status', '--porcelain'), '')
                        self.assertEqual((root / 'lib/main.dart').read_text(), 'fork code')
                    else:
                        sync(upstream)
                        head = git('rev-parse', 'HEAD')
                        self.assertEqual(len(git('rev-list', '--parents', '-n', '1', head).split()), 3)
                        self.assertIn('Fork section', (root / 'README.md').read_text())
                        self.assertIn('Upstream guide', (root / 'README.md').read_text())
                        self.assertEqual((root / '.github/workflows/ci.yml').read_text(), 'fork')
                        self.assertEqual(json.loads((root / 'assets/translation.json').read_text()),
                                         {'zh': {'base': 'new', 'fork': 'notice'}})
                        sync(upstream)
                        self.assertEqual(git('rev-parse', 'HEAD'), head)
            finally:
                os.chdir(previous)

    def test_real_merge_resolves_docs_translations_and_retains_ci(self):
        self.exercise_merge()

    def test_real_code_conflict_aborts_without_overwriting_fork(self):
        self.exercise_merge(code_conflict=True)


if __name__ == '__main__':
    unittest.main()
