from pathlib import Path
import tempfile
import unittest

from make_release_notes import generate


class ReleaseNotesTest(unittest.TestCase):
    def test_exact_version_sources_rebuilds_and_missing_translation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'release-notes').mkdir()
            (root / '.github/fork').mkdir(parents=True)
            (root / '.github/fork/release-notes.md').write_text('- 个人功能', encoding='utf-8')
            authored = root / 'release-notes/v2.3.12.zh-CN.md'
            authored.write_text('## 更新内容\n\n### 新增\n- 上游新功能', encoding='utf-8')
            (root / 'CHANGELOG.md').write_text(
                '## [v2.3.13](https://example.com)\n- 不能串版本\n'
                '## [v2.3.12](https://example.com)\n- 日志回退\n'
                '## [v2.3.11](https://example.com)\n- 旧日志', encoding='utf-8')
            result = generate(root, '2.3.12', '10030', 'v2.3.12+10025')
            self.assertIn('上游新功能', result)
            self.assertIn('重新构建', result)
            self.assertIn('个人功能', result)
            self.assertLess(result.index('上游更新（中文）'), result.index('个人修改（本 Fork）'))
            self.assertNotIn('不能串版本', result)
            authored.unlink()
            result = generate(root, '2.3.12', '10031')
            self.assertIn('日志回退', result)
            self.assertNotIn('旧日志', result)
            self.assertNotIn('不能串版本', result)
            result = generate(root, '2.3.14', '10032')
            self.assertIn('尚未提供', result)
            self.assertNotIn('日志回退', result)


if __name__ == '__main__':
    unittest.main()
