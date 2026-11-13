"""Generate Chinese release notes from the exact upstream version and fork notes."""
import argparse
import os
from pathlib import Path
import re


def upstream_notes(root, version):
    authored = root / 'release-notes' / f'v{version}.zh-CN.md'
    if authored.is_file() and authored.read_text(encoding='utf-8-sig').strip():
        return authored.read_text(encoding='utf-8-sig').strip(), f'release-notes/v{version}.zh-CN.md'
    changelog = root / 'CHANGELOG.md'
    text = changelog.read_text(encoding='utf-8-sig') if changelog.exists() else ''
    sections = re.split(r'(?=^## )', text, flags=re.MULTILINE)
    for section in sections:
        heading, _, body = section.partition('\n')
        if re.match(r'^## \[v?' + re.escape(version) + r'\](?:\(|\s|$)', heading):
            if body.strip():
                return body.strip(), 'CHANGELOG.md'
    return ('上游尚未提供此版本的中文更新说明，请查看上游发布页；'
            '此处不会使用其他版本的日志代替。', None)


def generate(root, version, build, previous_tag=''):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', version):
        raise ValueError('Invalid version')
    notes, source = upstream_notes(root, version)
    # The source document's own title is redundant inside our upstream section.
    notes = re.sub(r'^## (?:更新内容|更新內容)\s*\n', '', notes).strip()
    upstream_url = f'https://github.com/Kyosee/VeneraX/releases/tag/v{version}'
    same_version = previous_tag.lstrip('vV').split('+')[0] == version
    status = ('本次是同一上游版本的 Fork 重新构建；下方为该上游版本说明，不代表上游本次又发布了新版本。'
              if same_version else f'本包基于上游 VeneraX {version}，以下为该版本的中文说明。')
    provenance = f'\n\n中文说明来源：`{source}`。' if source else ''
    personal = (root / '.github/fork/release-notes.md').read_text(encoding='utf-8').strip()
    return (f'# VeneraX {version}+{build}\n\n'
            f'## 上游更新（中文）\n\n{status}\n\n{notes}{provenance}\n\n'
            f'[查看上游发布页]({upstream_url})\n\n'
            f'## 个人修改（本 Fork）\n\n'
            '以下为本 Fork 持续保留的功能与维护改动，并非每次构建都重新新增。\n\n'
            f'{personal}\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', default=os.environ.get('VERSION'), required='VERSION' not in os.environ)
    parser.add_argument('--build', default=os.environ.get('BUILD'), required='BUILD' not in os.environ)
    parser.add_argument('--previous-tag', default=os.environ.get('PREVIOUS_TAG', ''))
    parser.add_argument('--output', default='result/release-notes.md')
    args = parser.parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(generate(Path.cwd(), args.version, args.build, args.previous_tag), encoding='utf-8')
