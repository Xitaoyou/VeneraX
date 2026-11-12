"""Skip IPA publication only when every changed path is known metadata."""
import argparse
import fnmatch
import subprocess
import sys


def is_metadata(path):
    # doc/*.md and assets/*.md are bundled application resources, not metadata.
    if path in {
        'altstore-source.json', 'altstore-source-beta.json',
        '.github/fork/DESIGN.md', '.github/fork/release-notes.md',
        '.github/fork/readme.zh.md', '.github/fork/readme.en.md',
    }:
        return True
    return '/' not in path and any(fnmatch.fnmatchcase(path, pattern) for pattern in (
        'README*.md', 'CHANGELOG*.md', 'CONTRIBUTING.md',
        'CODE_OF_CONDUCT.md', 'SECURITY.md', 'LICENSE', 'LICENSE.*',
    ))


def should_build(base, head, force=False, cwd=None):
    if force:
        return True
    try:
        result = subprocess.run(
            ['git', 'diff', '--name-only', '--no-renames', '-z', base, head, '--'],
            cwd=cwd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError):
        # A missing/zero baseline must never silently suppress a release.
        return True
    paths = result.stdout.decode('utf-8', errors='replace').split('\0')
    return any(path and not is_metadata(path) for path in paths)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', required=True)
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    build = should_build(args.base, args.head, args.force)
    print('true' if build else 'false')
    print('IPA build required' if build else 'Only metadata changed (or no changes); skip IPA', file=sys.stderr)
