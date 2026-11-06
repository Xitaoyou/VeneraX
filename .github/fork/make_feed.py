import datetime
import json
import os
from pathlib import Path
from urllib.parse import quote

repo = os.environ['GITHUB_REPOSITORY']
version, build, tag = (os.environ[k] for k in ('VERSION', 'BUILD', 'TAG'))
ipa = next(Path('result').glob('*.ipa'))
icon = f'https://raw.githubusercontent.com/{repo}/master/assets/app_icon.png'
entry = {
    'version': version,
    'buildVersion': build,
    'date': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'downloadURL': f'https://github.com/{repo}/releases/download/{quote(tag)}/{quote(ipa.name)}',
    'size': ipa.stat().st_size,
    'minOSVersion': '15.1',
    'localizedDescription': '个人 fork：漫画阅读器、封面和图片预览下滑返回。',
}
feed = {
    'name': 'VeneraX · Xitaoyou',
    'identifier': 'io.github.xitaoyou.venerax.source',
    'iconURL': icon,
    'apps': [{
        'name': 'VeneraX',
        'bundleIdentifier': 'io.github.kyosee.venera',
        'developerName': 'Xitaoyou / VeneraX contributors',
        'localizedDescription': entry['localizedDescription'],
        'iconURL': icon,
        'versions': [entry],
        'appPermissions': {'entitlements': [], 'privacy': {}},
    }],
    'news': [],
}
Path('result/altstore-source.json').write_text(
    json.dumps(feed, ensure_ascii=False, indent=2) + '\n', encoding='utf-8'
)
