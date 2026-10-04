"""Acquire a declared, sized, SHA256-pinned asset into the external source cache.

No discovery, guessed URL, or automatic large download. --max-bytes is a hard
budget; a partial file is never accepted as an input by the preparation pipeline.
"""
import argparse
import os
from pathlib import Path
import re
from urllib.request import Request, urlopen

from pipeline_io import digest


def fetch(url, output, sha256, size_bytes, max_bytes):
    if not url.startswith('https://') or not re.fullmatch('[0-9a-f]{64}', sha256):
        raise ValueError('Explicit HTTPS URL and producer/verified SHA256 required')
    if not 0 < size_bytes <= max_bytes:
        raise ValueError('Declared size exceeds download budget')
    if output.exists() and digest(output) == sha256:
        return output
    output.parent.mkdir(parents=True, exist_ok=True)
    partial = output.with_suffix(output.suffix + '.part')
    offset = partial.stat().st_size if partial.exists() else 0
    if offset > size_bytes:
        raise ValueError('Partial download is larger than declared source')
    if offset < size_bytes:
        headers = {'User-Agent': 'NoWave-cartography/1.0', 'Accept-Encoding': 'identity'}
        if offset:
            headers['Range'] = f'bytes={offset}-'
        with urlopen(Request(url, headers=headers), timeout=120) as response:
            if offset and (response.status != 206 or not response.headers.get('Content-Range', '').startswith(f'bytes {offset}-')):
                raise ValueError('Server did not honor resume range; remove only this .part to restart')
            with partial.open('ab' if offset else 'wb') as stream:
                total = offset
                while chunk := response.read(1024 * 1024):
                    total += len(chunk)
                    if total > size_bytes:
                        raise ValueError('Server exceeded declared size')
                    stream.write(chunk)
    if partial.stat().st_size != size_bytes or digest(partial) != sha256:
        raise ValueError('Incomplete source or SHA256 mismatch; output not published')
    os.replace(partial, output)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--size-bytes', type=int, required=True)
    parser.add_argument('--max-bytes', type=int, default=512 * 1024 * 1024)
    args = parser.parse_args()
    print(fetch(args.url, args.output, args.sha256, args.size_bytes, args.max_bytes))


if __name__ == '__main__':
    main()
