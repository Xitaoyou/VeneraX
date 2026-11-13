import datetime
import json
import os
import plistlib
import zipfile
from pathlib import Path
from urllib.parse import quote

repo = os.environ['GITHUB_REPOSITORY']
version, build, tag = (os.environ[k] for k in ('VERSION', 'BUILD', 'TAG'))
ipa = next(Path('result').glob('*.ipa'))
with zipfile.ZipFile(ipa) as package:
    info = plistlib.loads(package.read('Payload/Runner.app/Info.plist'))
assert info['CFBundleShortVersionString'] == version
assert str(info['CFBundleVersion']) == build
privacy = {k: v for k, v in info.items()
           if k.startswith('NS') and k.endswith('UsageDescription')}
icon = f'https://raw.githubusercontent.com/{repo}/master/assets/app_icon.png'
notes = Path('result/release-notes.md')
release_description = notes.read_text(encoding='utf-8') if notes.exists() else '个人 iOS Fork：支持下滑返回。'
entry = {
    'version': version,
    'buildVersion': build,
    'date': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'downloadURL': f'https://github.com/{repo}/releases/download/{quote(tag)}/{quote(ipa.name)}',
    'size': ipa.stat().st_size,
    'minOSVersion': info.get('MinimumOSVersion', '15.1'),
    'localizedDescription': release_description,
}
feed = {
    'name': 'VeneraX · Xitaoyou',
    'identifier': 'io.github.xitaoyou.venerax.source',
    'iconURL': icon,
    'apps': [{
        'name': 'VeneraX',
        'bundleIdentifier': info['CFBundleIdentifier'],
        'developerName': 'Xitaoyou / VeneraX contributors',
        'localizedDescription': '个人 iOS Fork：漫画阅读器、封面与图片预览下滑返回。',
        'iconURL': icon,
        'versions': [entry],
        'appPermissions': {'entitlements': [], 'privacy': privacy},
    }],
    'news': [],
}
Path('result/altstore-source.json').write_text(
    json.dumps(feed, ensure_ascii=False, indent=2) + '\n', encoding='utf-8'
)
