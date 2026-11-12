import subprocess
import tempfile
import unittest
from pathlib import Path

from should_build import is_metadata, should_build


class BuildFilterTest(unittest.TestCase):
    def test_path_policy(self):
        for path in ['README_EN.md', 'CHANGELOG.md', 'altstore-source.json',
                     '.github/fork/DESIGN.md', '.github/fork/release-notes.md',
                     '.github/fork/readme.zh.md', '.github/fork/readme.en.md']:
            with self.subTest(path=path):
                self.assertTrue(is_metadata(path))
        for path in ['lib/main.dart', 'assets/help.md', 'doc/guide.zh.md',
                     'pubspec.yaml', 'pubspec.lock', 'ios/Podfile',
                     '.github/workflows/fork-ios.yml', '.github/fork/make_feed.py',
                     '.github/fork/should_build.py', 'new-unknown-file']:
            with self.subTest(path=path):
                self.assertFalse(is_metadata(path))

    def test_git_changes_and_fallbacks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)

            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root).decode().strip()

            def commit():
                git('add', '-A')
                git('-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                    '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture')
                return git('rev-parse', 'HEAD')

            git('init', '-q')
            (root / 'README.md').write_text('first')
            base = commit()
            (root / 'README.md').write_text('second')
            (root / 'altstore-source.json').write_text('{}')
            metadata = commit()
            self.assertFalse(should_build(base, metadata, cwd=root))
            self.assertFalse(should_build(metadata, metadata, cwd=root))
            self.assertTrue(should_build(base, metadata, force=True, cwd=root))
            self.assertTrue(should_build('0' * 40, metadata, cwd=root))
            (root / 'README.md').rename(root / 'runtime.md')
            renamed = commit()
            self.assertTrue(should_build(metadata, renamed, cwd=root))
            (root / 'runtime.md').unlink()
            deleted = commit()
            self.assertTrue(should_build(renamed, deleted, cwd=root))
            (root / 'doc').mkdir()
            (root / 'doc/guide.zh.md').write_text('bundled help')
            bundled = commit()
            self.assertTrue(should_build(deleted, bundled, cwd=root))


if __name__ == '__main__':
    unittest.main()
