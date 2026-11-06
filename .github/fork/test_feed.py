import json
import os
import plistlib
import runpy
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch


class FeedTest(unittest.TestCase):
    def test_feed_matches_the_actual_ipa(self):
        script = Path(__file__).with_name('make_feed.py').resolve()
        with tempfile.TemporaryDirectory() as temp:
            previous = Path.cwd()
            try:
                os.chdir(temp)
                Path('result').mkdir()
                ipa = Path('result/VeneraX-ios-2.3.10+10002.ipa')
                info = {
                    'CFBundleIdentifier': 'io.github.kyosee.venera',
                    'CFBundleShortVersionString': '2.3.10',
                    'CFBundleVersion': '10002',
                    'MinimumOSVersion': '15.1',
                    'NSCameraUsageDescription': 'Scan sync QR codes.',
                    'NSPhotoLibraryUsageDescription': 'Choose images.',
                    'NSFaceIDUsageDescription': 'Unlock the app.',
                }
                with zipfile.ZipFile(ipa, 'w') as package:
                    package.writestr('Payload/Runner.app/Info.plist',
                                     plistlib.dumps(info))
                with patch.dict(os.environ, {
                    'GITHUB_REPOSITORY': 'Xitaoyou/VeneraX',
                    'VERSION': '2.3.10', 'BUILD': '10002',
                    'TAG': 'v2.3.10+10002',
                }):
                    runpy.run_path(str(script), run_name='__main__')
                feed = json.loads(Path('result/altstore-source.json').read_text(
                    encoding='utf-8'))
                app = feed['apps'][0]
                entry = app['versions'][0]
                self.assertEqual(app['bundleIdentifier'], info['CFBundleIdentifier'])
                self.assertEqual(app['appPermissions']['privacy'], {
                    k: v for k, v in info.items() if k.startswith('NS')
                })
                self.assertEqual(entry['buildVersion'], '10002')
                self.assertEqual(entry['size'], ipa.stat().st_size)
                self.assertIn('/Xitaoyou/VeneraX/releases/download/', entry['downloadURL'])
                self.assertIn('v2.3.10%2B10002', entry['downloadURL'])
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
