#!/usr/bin/env python3
"""Inspect an A/B OTA zip over HTTP range requests, without downloading it.

  ota_peek.py <url>               partition table: size + compressed bytes to fetch
  ota_peek.py <url> --dump PART [--out FILE]
                                  rebuild one partition image (full-OTA ops only)

OnePlus' CDN wants okhttp headers; they are sent on every request.
"""
import argparse
import bz2
import lzma
import struct
import sys
import urllib.request
import zipfile
import io

HEADERS = {'User-Agent': 'okhttp/3.12.12', 'userId': 'oplus-ota|16002018'}


def resolve(url):
    req = urllib.request.Request(url, headers={**HEADERS, 'Range': 'bytes=0-0'})
    with urllib.request.urlopen(req) as r:
        return r.geturl(), int(r.headers['Content-Range'].rsplit('/', 1)[1])


class Remote:
    def __init__(self, url):
        self.url, self.size = resolve(url)
        self.fetched = 0

    def read(self, off, n):
        req = urllib.request.Request(self.url, headers={**HEADERS, 'Range': f'bytes={off}-{off + n - 1}'})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        self.fetched += len(data)
        return data


class RangeFile(io.RawIOBase):
    def __init__(self, remote):
        self.r, self.pos = remote, 0

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos

    def seek(self, off, whence=0):
        self.pos = {0: off, 1: self.pos + off, 2: self.r.size + off}[whence]
        return self.pos

    def readinto(self, b):
        n = min(len(b), self.r.size - self.pos)
        if n <= 0:
            return 0
        data = self.r.read(self.pos, n)
        b[:len(data)] = data
        self.pos += len(data)
        return len(data)


# Minimal protobuf reader: enough of DeltaArchiveManifest for full OTAs
def varint(b, i):
    v = s = 0
    while True:
        c = b[i]; i += 1
        v |= (c & 0x7f) << s; s += 7
        if c < 0x80:
            return v, i


def fields(b):
    i = 0
    while i < len(b):
        key, i = varint(b, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, i = varint(b, i)
        elif wt == 2:
            n, i = varint(b, i); v = b[i:i + n]; i += n
        elif wt == 1:
            v = b[i:i + 8]; i += 8
        elif wt == 5:
            v = b[i:i + 4]; i += 4
        else:
            raise ValueError(f'wire type {wt}')
        yield f, v


def parse_manifest(m):
    block_size, parts = 4096, []
    for f, v in fields(m):
        if f == 3:
            block_size = v
        elif f == 13:
            p = {'name': '', 'size': 0, 'ops': []}
            for pf, pv in fields(v):
                if pf == 1:
                    p['name'] = pv.decode()
                elif pf == 7:
                    p['size'] = dict(fields(pv)).get(1, 0)
                elif pf == 8:
                    op = {'type': 0, 'off': 0, 'len': 0, 'dst': []}
                    for of, ov in fields(pv):
                        if of == 1: op['type'] = ov
                        elif of == 2: op['off'] = ov
                        elif of == 3: op['len'] = ov
                        elif of == 6:
                            e = dict(fields(ov)); op['dst'].append((e.get(1, 0), e.get(2, 0)))
                    p['ops'].append(op)
            parts.append(p)
    return block_size, parts


def open_payload(url):
    remote = Remote(url)
    zf = zipfile.ZipFile(io.BufferedReader(RangeFile(remote), buffer_size=1 << 16))
    info = zf.getinfo('payload.bin')
    if info.compress_type != zipfile.ZIP_STORED:
        sys.exit('payload.bin is compressed inside the zip; range reads would not work')
    # Local header: 30 bytes + name + extra
    lh = remote.read(info.header_offset, 30)
    n, x = struct.unpack('<HH', lh[26:30])
    base = info.header_offset + 30 + n + x
    hdr = remote.read(base, 24)
    if hdr[:4] != b'CrAU':
        sys.exit('not a payload.bin')
    ver, msize = struct.unpack('>QQ', hdr[4:20])
    sig = struct.unpack('>I', hdr[20:24])[0] if ver >= 2 else 0
    hlen = 24 if ver >= 2 else 20
    manifest = remote.read(base + hlen, msize)
    data_start = base + hlen + msize + sig
    return remote, data_start, *parse_manifest(manifest)


# update_metadata.proto InstallOperation types used by full OTAs
DECOMP = {0: lambda d: d, 1: bz2.decompress, 8: lzma.decompress}  # REPLACE, REPLACE_BZ, REPLACE_XZ
SKIP = {6, 7}  # ZERO, DISCARD


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('url')
    ap.add_argument('--dump')
    ap.add_argument('--out')
    a = ap.parse_args()
    remote, data_start, bs, parts = open_payload(a.url)
    print(f'zip {remote.size / 2**30:.2f} GiB, block size {bs}, {len(parts)} partitions '
          f'(read {remote.fetched / 1024:.0f} KiB so far)', file=sys.stderr)
    if not a.dump:
        from collections import Counter
        print('op types:', dict(Counter(o['type'] for p in parts for o in p['ops'])), file=sys.stderr)
        print(f'{"partition":<20} {"image":>12} {"to fetch":>12}')
        for p in sorted(parts, key=lambda p: -sum(o['len'] for o in p['ops'])):
            print(f'{p["name"]:<20} {p["size"] / 2**20:>10.1f}MB {sum(o["len"] for o in p["ops"]) / 2**20:>10.1f}MB')
        return
    p = next((p for p in parts if p['name'] == a.dump), None)
    if not p:
        sys.exit(f'no partition {a.dump}')
    total = sum(o['len'] for o in p['ops'])
    out = a.out or f'{a.dump}.img'
    print(f'{a.dump}: {len(p["ops"])} ops, fetching {total / 2**20:.1f} MB -> {out}', file=sys.stderr)
    with open(out, 'wb') as f:
        f.truncate(p['size'])
        done = 0
        for i, o in enumerate(p['ops']):
            if o['type'] in SKIP:
                continue
            fn = DECOMP.get(o['type'])
            if fn is None:
                sys.exit(f'op type {o["type"]} unsupported (incremental OTA?)')
            data = fn(remote.read(data_start + o['off'], o['len'])) if o['len'] else b''
            pos = 0
            for start, nblk in o['dst']:
                f.seek(start * bs)
                f.write(data[pos:pos + nblk * bs]); pos += nblk * bs
            done += o['len']
            print(f'\r  {done / 2**20:7.1f} / {total / 2**20:.1f} MB  ({i + 1}/{len(p["ops"])} ops)',
                  end='', file=sys.stderr, flush=True)
    print(file=sys.stderr)


if __name__ == '__main__':
    main()
