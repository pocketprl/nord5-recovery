#!/usr/bin/env python3
"""Pull single files out of a partition inside a remote OTA, fetching only the
payload chunks those files (and their metadata) live in.

  erofs_lazy.py [--fs erofs|vfat] [--list] <ota-url> <partition> <workdir> [/path ...]

  --fs erofs  (default) system/vendor/odm/...; read with dump.erofs
  --fs vfat   modem and other FAT partitions; read with mtools
  --list      list instead of extracting: vfat prints the whole tree, erofs
              lists each given directory

How: keep a sparse local copy of the partition image. Run the filesystem tool
under strace, follow its openat/lseek/read/pread64 on the image, find the first
byte range it read from a chunk we don't have, fetch and decompress just that
chunk, repeat. Once a run reads nothing missing, the output is exact. Only the
first missing chunk is fetched per round, because reads past an unfetched
chunk follow garbage pointers. Progress persists in <workdir>, so an
interrupted run resumes.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ota_peek as op  # noqa: E402

OPENAT = re.compile(r'^openat\([^,]+, "([^"]+)", [^)]*\) = (\d+)')
CLOSE = re.compile(r'^close\((\d+)\)')
LSEEK = re.compile(r'^lseek\((\d+), -?\d+, \w+\) = (\d+)')
READ = re.compile(r'^read\((\d+), .*, (\d+)\) = (\d+)$')
PREAD = re.compile(r'^pread64\((\d+), .*, (\d+), (\d+)\) = (\d+)$')


def reads_from(trace, img):
    """Yield (offset, length) of every read the traced tool made on img."""
    fds, pos = set(), {}
    real = os.path.realpath(img)
    for line in trace:
        line = line.rstrip('\n')
        if m := OPENAT.match(line):
            if os.path.realpath(m.group(1)) == real:
                fd = int(m.group(2)); fds.add(fd); pos[fd] = 0
        elif m := CLOSE.match(line):
            fds.discard(int(m.group(1)))
        elif m := LSEEK.match(line):
            fd = int(m.group(1))
            if fd in fds: pos[fd] = int(m.group(2))
        elif m := PREAD.match(line):
            if int(m.group(1)) in fds:
                yield int(m.group(3)), max(int(m.group(2)), 1)
        elif m := READ.match(line):
            fd = int(m.group(1))
            if fd in fds:
                yield pos[fd], max(int(m.group(2)), 1)
                pos[fd] += int(m.group(3))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--fs', choices=['erofs', 'vfat'], default='erofs')
    ap.add_argument('--list', action='store_true')
    ap.add_argument('url'); ap.add_argument('part'); ap.add_argument('work')
    ap.add_argument('paths', nargs='*')
    a = ap.parse_args()
    os.makedirs(a.work, exist_ok=True)
    remote, data_start, bs, parts = op.open_payload(a.url)
    p = next(x for x in parts if x['name'] == a.part)
    img = os.path.join(a.work, f'{a.part}.img')
    state_f = os.path.join(a.work, f'{a.part}.fetched.json')
    fetched = set(json.load(open(state_f))) if os.path.exists(state_f) else set()
    if not os.path.exists(img):
        with open(img, 'wb') as f:
            f.truncate(p['size'])
    owner = {}  # block -> op index
    for i, o in enumerate(p['ops']):
        for start, n in o['dst']:
            for b in range(start, start + n):
                owner[b] = i
    print(f'{a.part}: {p["size"] / 2**20:.0f} MB image, {len(p["ops"])} chunks, '
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
            res = subprocess.run(['strace', '-qq', '-e', 'trace=openat,close,lseek,read,pread64',
                                  '-o', t.name, *cmd], capture_output=True)
            for off, n in reads_from(t, img):
                for b in range(off // bs, (off + n - 1) // bs + 1):
                    i = owner.get(b)
                    if i is not None and i not in fetched:
                        return i, res
        return None, res

    def commands(path):
        if a.fs == 'erofs':
            if a.list:
                return [['dump.erofs', f'--path={path}', img], ['dump.erofs', '--ls', f'--path={path}', img]]
            return [['dump.erofs', f'--path={path}', img], ['dump.erofs', '--cat', f'--path={path}', img]]
        if a.list:
            return [['mdir', '-a', '-i', img, f'::{path}']] if a.paths else [['mdir', '-/', '-a', '-i', img, '::/']]
        return [['mcopy', '-n', '-i', img, f'::{path}', '-']]

    if owner[0] not in fetched:
        fetch(owner[0])  # superblock / boot sector
    out_dir = os.path.join(a.work, 'files', a.part)
    for path in (['/'] if a.list and a.fs == 'vfat' and not a.paths else a.paths):
        rounds = got = 0
        while True:
            for cmd in commands(path):
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
            print(f'\n  {path}: {cmd[0]} failed: {res.stderr.decode(errors="replace").strip()[:200]}',
                  file=sys.stderr)
            continue
        if a.list:
            sys.stdout.write(res.stdout.decode(errors='replace'))
            print(f'\n  listing: OK', file=sys.stderr)
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
