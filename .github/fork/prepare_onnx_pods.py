"""Prepare pinned ORT 1.23.0 CocoaPods without download.onnxruntime.ai.

The plugin maintainer's library-format archive contains Microsoft's same 1.23.0
binaries. Both downloads are pinned and verified before anything is extracted.
Podspecs are the original CocoaPods 1.23.0 specs; only delivery is overridden.
"""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

BINARY_URL = ('https://github.com/masicai/onnxruntime-swift-package-manager/'
              'releases/download/1.23.1/onnxruntime-libs-1.23.0.zip')
BINARY_SHA = '4bd86356e2d5aab1b8ece609bb9caa63161a6d79d21244da007f9fda6830ff3b'
SOURCE_REV = '57f28b1fdd6fe33585370b146a46c597d6750953'
SOURCE_URL = ('https://codeload.github.com/masicai/'
              f'onnxruntime-swift-package-manager/zip/{SOURCE_REV}')
SOURCE_SHA = '41fea3a987a94e7c7ffb199d336c855ceb0e13c8216dec1487624e33661d0778'


def verify(path, expected):
    with path.open('rb') as source:
        digest = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError(f'ONNX checksum mismatch: {path.name}')


def extract(archive, destination):
    with zipfile.ZipFile(archive) as source:
        root = destination.resolve()
        for entry in source.infolist():
            if not (root / entry.filename).resolve().is_relative_to(root):
                raise ValueError('Unsafe ONNX archive path')
        source.extractall(destination)


def prepare(binary, bindings, output):
    verify(binary, BINARY_SHA)
    verify(bindings, SOURCE_SHA)
    output.mkdir(parents=True, exist_ok=True)
    c_pod = output / 'onnxruntime-c'
    objc_pod = output / 'onnxruntime-objc'
    extract(binary, c_pod)
    # Preserve the public header layout expected by the original C podspec.
    shutil.copytree(c_pod / 'onnxruntime.xcframework/ios-arm64/Headers/onnxruntime',
                    c_pod / 'Headers', dirs_exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        source = Path(temp)
        extract(bindings, source)
        source = source / f'onnxruntime-swift-package-manager-{SOURCE_REV}'
        shutil.copytree(source / 'objectivec', objc_pod / 'objectivec', dirs_exist_ok=True)
        for target in (c_pod, objc_pod):
            shutil.copy2(source / 'LICENSE', target / 'LICENSE')
    specs = Path(__file__).parent / 'onnx'
    for target in (c_pod, objc_pod):
        shutil.copy2(specs / f'{target.name}.podspec.json', target)
    print(f'Prepared verified ONNX Runtime 1.23.0 pods in {output}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--bindings', type=Path)
    parser.add_argument('--output', type=Path,
                        default=Path('ios/Flutter/ephemeral/fork_onnx'))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temp:
        paths = []
        for supplied, url, name in ((args.binary, BINARY_URL, 'binary.zip'),
                                    (args.bindings, SOURCE_URL, 'bindings.zip')):
            path = supplied or Path(temp) / name
            if not supplied:
                subprocess.run(['curl', '--fail', '--location', '--retry', '3',
                                '--connect-timeout', '30', '--max-time', '300',
                                '--output', str(path), url], check=True)
            paths.append(path)
        prepare(*paths, args.output)


if __name__ == '__main__':
    main()
