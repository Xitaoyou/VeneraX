"""Merge upstream, resolving only fork documentation and independent JSON edits."""
import argparse
import json
import os
from pathlib import Path
import subprocess

MISSING = object()


def merge_json(base, ours, theirs, path=''):
    if ours == theirs:
        return ours
    if ours == base:
        return theirs
    if theirs == base:
        return ours
    if all(isinstance(value, dict) for value in (base, ours, theirs)):
        result = {}
        for key in dict.fromkeys([*theirs, *ours, *base]):
            value = merge_json(base.get(key, MISSING), ours.get(key, MISSING),
                               theirs.get(key, MISSING), f'{path}/{key}')
            if value is not MISSING:
                result[key] = value
        return result
    raise ValueError(f'Both sides changed translation {path}')


def render_readme(upstream, fragment):
    end = upstream.index('</div>') + len('</div>')
    header, body = upstream[:end], upstream[end:]
    header = header.replace('<h1>VeneraX</h1>', '<h1>VeneraX · Personal iOS Fork</h1>')
    header = header.replace('[![Stars]', '[![Upstream Stars]')
    header = header.replace(
        '[![Release](https://img.shields.io/github/v/release/Kyosee/VeneraX)](https://github.com/Kyosee/VeneraX/releases)',
        '[![Fork Release](https://img.shields.io/github/v/release/Xitaoyou/VeneraX)](https://github.com/Xitaoyou/VeneraX/releases)\n'
        '[![Fork iOS](https://github.com/Xitaoyou/VeneraX/actions/workflows/fork-ios.yml/badge.svg)](https://github.com/Xitaoyou/VeneraX/actions/workflows/fork-ios.yml)')
    return header + '\n\n' + fragment.strip() + '\n\n' + body.lstrip('\r\n')


def git(*args, check=True):
    return subprocess.run(['git', *args], check=check, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE).stdout.decode('utf-8-sig')


def report(message):
    print(message)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as out:
            out.write(message + '\n')


def sync(upstream):
    # Resolve and validate refs before entering a merge. Never overwrite code.
    upstream = git('rev-parse', '--verify', upstream + '^{commit}').strip()
    if subprocess.run(['git', 'merge-base', '--is-ancestor', upstream, 'HEAD']).returncode == 0:
        return
    base = git('merge-base', 'HEAD', upstream).strip()
    if git('status', '--porcelain').strip():
        raise RuntimeError('Upstream sync requires a clean working tree')
    try:
        git('merge', '--no-commit', '--no-ff', upstream, check=False)
        git('rev-parse', '--verify', 'MERGE_HEAD')
        git('restore', '--source=HEAD', '--staged', '--worktree', '--', '.github')
        for name, language in [('README.md', 'zh'), ('README_EN.md', 'en')]:
            fragment = Path(f'.github/fork/readme.{language}.md').read_text(encoding='utf-8')
            Path(name).write_text(render_readme(git('show', f'{upstream}:{name}'), fragment), encoding='utf-8')
            git('add', '--', name)
        conflicts = git('diff', '--name-only', '--diff-filter=U').splitlines()
        translation = 'assets/translation.json'
        if translation in conflicts:
            try:
                sides = [json.loads(git('show', f'{ref}:{translation}'))
                         for ref in (base, 'HEAD', upstream)]
                merged = merge_json(*sides)
                Path(translation).write_text(json.dumps(merged, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
                git('add', '--', translation)
            except ValueError as error:
                report(str(error))
        conflicts = git('diff', '--name-only', '--diff-filter=U').splitlines()
        if conflicts:
            raise RuntimeError('Manual resolution required:\n' + '\n'.join(f'- `{p}`' for p in conflicts))
        git('commit', '-m', 'Merge Kyosee/VeneraX master into personal iOS fork')
        report('Upstream merged; fork documentation retained and upstream README refreshed.')
    except Exception as error:
        git('merge', '--abort', check=False)
        report('Upstream sync stopped safely.\n\n' + str(error))
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('upstream')
    sync(parser.parse_args().upstream)
