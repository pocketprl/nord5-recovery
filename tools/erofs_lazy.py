#!/usr/bin/env python3
"""Pull single files out of an erofs partition inside a remote OTA, fetching
only the payload chunks those files (and their metadata) live in.

  erofs_lazy.py <ota-url> <partition> <workdir> /path/in/partition [...]

How: keep a sparse local copy of the partition image. Run dump.erofs --cat
under strace, find the first byte range it read from a chunk we don't have,
fetch and decompress just that chunk, repeat. Once a run reads nothing
missing, the output is exact. Only the first missing chunk is fetched per
round, because reads past an unfetched chunk follow garbage pointers.
Progress persists in <workdir>, so an interrupted run resumes.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ota_peek as op  # noqa: E402

PREAD = re.compile(r'pread64\(\d+, .*, (\d+), (\d+)\) = (\d+)')


def main():
    url, part, work, *paths = sys.argv[1:]
    os.makedirs(work, exist_ok=True)
    remote, data_start, bs, parts = op.open_payload(url)
    p = next(x for x in parts if x['name'] == part)
    img = os.path.join(work, f'{part}.img')
    state_f = os.path.join(work, f'{part}.fetched.json')
    fetched = set(json.load(open(state_f))) if os.path.exists(state_f) else set()
    if not os.path.exists(img):
        with open(img, 'wb') as f:
            f.truncate(p['size'])
    # block -> op index
    owner = {}
    for i, o in enumerate(p['ops']):
        for start, n in o['dst']:
            for b in range(start, start + n):
                owner[b] = i
    print(f'{part}: {p["size"] / 2**20:.0f} MB image, {len(p["ops"])} chunks, '
          f'{len(fetched)} already local', file=sys.stderr)

    def fetch(i):
        o = p['ops'][i]
        if o['type'] in op.SKIP:
            fetched.add(i)
            return 0
        data = op.DECOMP[o['type']](remote.read(data_start + o['off'], o['len']))
        with open(img, 'r+b') as f:
            pos = 0
            for start, n in o['dst']:
                f.seek(start * bs)
                f.write(data[pos:pos + n * bs])
                pos += n * bs
        fetched.add(i)
        json.dump(sorted(fetched), open(state_f, 'w'))
        return o['len']

    def first_missing(cmd):
        with tempfile.NamedTemporaryFile('r', suffix='.strace') as t:
            res = subprocess.run(['strace', '-qq', '-e', 'trace=pread64', '-o', t.name, *cmd],
                                 capture_output=True)
            for line in t:
                m = PREAD.search(line)
                if not m:
                    continue
                count, off = int(m.group(1)), int(m.group(2))
                for b in range(off // bs, (off + max(count, 1) - 1) // bs + 1):
                    i = owner.get(b)
                    if i is not None and i not in fetched:
                        return i, res
        return None, res

    # Superblock first
    fetch(owner[0])
    out_dir = os.path.join(work, 'files', part)
    for path in paths:
        rounds = got = 0
        while True:
            # Resolve the inode (walks directories), then cat the file
            for cmd in (['dump.erofs', f'--path={path}', img],
                        ['dump.erofs', '--cat', f'--path={path}', img]):
                i, res = first_missing(cmd)
                if i is not None:
                    break
            if i is None:
                break
            got += fetch(i)
            rounds += 1
            print(f'\r  {path}: {rounds} chunks, {got / 2**20:.1f} MB '
                  f'(total fetched {remote.fetched / 2**20:.1f} MB)', end='', file=sys.stderr, flush=True)
        if res.returncode != 0:
            print(f'\n  {path}: dump.erofs failed: {res.stderr.decode(errors="replace").strip()[:200]}',
                  file=sys.stderr)
            continue
        dest = os.path.join(out_dir, path.lstrip('/'))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, 'wb') as f:
            f.write(res.stdout)
        print(f'\n  {path}: OK, {len(res.stdout)} bytes -> {dest}', file=sys.stderr)
    print(f'done: {remote.fetched / 2**20:.1f} MB downloaded this run, '
          f'{len(fetched)}/{len(p["ops"])} chunks local', file=sys.stderr)


if __name__ == '__main__':
    main()
