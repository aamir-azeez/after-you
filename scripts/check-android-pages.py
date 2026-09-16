"""Check every packaged native ELF; no extraction or third-party dependencies."""
import argparse
import json
import struct
import zipfile

PAGE = 16384


def check_elf(data, name):
    if data[:4] != b'\x7fELF' or data[4] not in (1, 2) or data[5] != 1:
        raise ValueError(f'{name}: unsupported ELF header')
    bits = data[4]
    if bits == 2:
        offset = struct.unpack_from('<Q', data, 32)[0]
        size, count = struct.unpack_from('<HH', data, 54)
        layout = '<IIQQQQQQ'
    else:
        offset = struct.unpack_from('<I', data, 28)[0]
        size, count = struct.unpack_from('<HH', data, 42)
        layout = '<IIIIIIII'
    if not count or size < struct.calcsize(layout) or offset + count * size > len(data):
        raise ValueError(f'{name}: invalid program header table')
    loads = []
    relros = []
    for index in range(count):
        row = struct.unpack_from(layout, data, offset + index * size)
        if bits == 2:
            kind, flags, file_offset, address, _, file_size, memory_size, alignment = row
        else:
            kind, file_offset, address, _, file_size, memory_size, flags, alignment = row
        if kind == 1:
            loads.append((address, address + memory_size, flags))
            if alignment < PAGE or alignment & (alignment - 1) or (address - file_offset) % PAGE:
                raise ValueError(f'{name}: PT_LOAD is not 16 KB aligned')
            if file_offset + file_size > len(data) or file_size > memory_size:
                raise ValueError(f'{name}: invalid PT_LOAD bounds')
        if kind == 0x6474E552:
            relros.append((address, address + memory_size))
    if not loads:
        raise ValueError(f'{name}: no load segments')
    # Android rounds RELRO outward to whole pages (bionic/linker/linker_phdr.cpp,
    # _phdr_table_set_gnu_relro_prot). NDK runtimes can end RELRO inside padding;
    # that is safe only when rounding does not cover other writable LOAD bytes.
    for start, end in relros:
        protected_start = start // PAGE * PAGE
        protected_end = (end + PAGE - 1) // PAGE * PAGE
        for load_start, load_end, flags in loads:
            if not flags & 2:
                continue
            for pad_start, pad_end in ((protected_start, start), (end, protected_end)):
                if max(load_start, pad_start) < min(load_end, pad_end):
                    raise ValueError(f'{name}: GNU_RELRO rounding covers writable data')
    return {'path': name, 'elf_bits': 64 if bits == 2 else 32,
            'load_segments': len(loads), 'relro_ranges_checked': len(relros)}


def check_archive(path):
    with zipfile.ZipFile(path) as archive:
        entries = [entry for entry in archive.infolist() if entry.filename.endswith('.so')]
        if not entries or len({entry.filename for entry in entries}) != len(entries):
            raise ValueError('Missing or duplicate native libraries')
        return [check_elf(archive.read(entry), entry.filename) for entry in entries]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive')
    args = parser.parse_args()
    print(json.dumps({'page_size': PAGE, 'libraries': check_archive(args.archive)}, indent=2))
