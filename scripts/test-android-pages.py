"""Small ELF fixtures verify rejection of a genuinely incompatible binary layout."""
import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('pages', Path(__file__).with_name('check-android-pages.py'))
pages = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pages)


def elf(alignment=16384, address=0, relro_end=16384, memory_size=16384):
    data = bytearray(512)
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 2)
    struct.pack_into('<IIQQQQQQ', data, 64, 1, 6, 0, address, 0, 512, memory_size, alignment)
    struct.pack_into('<IIQQQQQQ', data, 120, 0x6474E552, 4, 0, 0, 0, 0, relro_end, 1)
    return data


class Pages(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(pages.check_elf(elf(), 'synthetic.so')['load_segments'], 1)

    def test_four_kib(self):
        with self.assertRaisesRegex(ValueError, 'PT_LOAD'):
            pages.check_elf(elf(alignment=4096), 'synthetic.so')

    def test_incongruent(self):
        with self.assertRaisesRegex(ValueError, 'PT_LOAD'):
            pages.check_elf(elf(address=4096), 'synthetic.so')

    def test_relro(self):
        with self.assertRaisesRegex(ValueError, 'GNU_RELRO'):
            pages.check_elf(elf(relro_end=4096), 'synthetic.so')

    def test_relro_padding_gap(self):
        self.assertEqual(pages.check_elf(elf(relro_end=4096, memory_size=4096), 'synthetic.so')['relro_ranges_checked'], 1)

    def test_truncated(self):
        with self.assertRaises(ValueError):
            pages.check_elf(elf()[:90], 'synthetic.so')


if __name__ == '__main__':
    unittest.main()
