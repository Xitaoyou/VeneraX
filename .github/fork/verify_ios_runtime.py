"""Reject an iOS build that cannot provide rhttp's runtime-loaded Rust library."""
import argparse
from pathlib import Path
import subprocess


def verify(app):
    binary = app / 'Frameworks/rhttp.framework/rhttp'
    if not binary.is_file():
        raise RuntimeError('Missing rhttp.framework/rhttp: network requests would fail on device')
    header = subprocess.check_output(['xcrun', 'otool', '-hv', str(binary)], text=True)
    if 'DYLIB' not in header:
        raise RuntimeError('rhttp must be a dynamic Mach-O library, not a static archive')
    symbols = subprocess.check_output(['xcrun', 'nm', '-gU', str(binary)], text=True)
    if '_frb_get_rust_content_hash' not in symbols:
        raise RuntimeError('rhttp is missing its flutter_rust_bridge entry point')
    if '_frbgen_rhttp_' not in symbols:
        raise RuntimeError('rhttp is missing its generated Rust API symbols')
    print('Verified embedded rhttp dynamic library and Rust bridge symbols')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    verify(parser.parse_args().app)
