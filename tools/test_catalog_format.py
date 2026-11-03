import struct
import unittest
from deploy_catalog import encode_catalog, validate_bmp

class CatalogFormatTests(unittest.TestCase):
    def test_counts_and_checksum(self):
        for n in [1,12,64]:
            addresses=[1000000+i*1801 for i in range(n)]
            b=encode_catalog(addresses,7)
            self.assertEqual(len(b),512)
            self.assertEqual(struct.unpack_from('<4sIII',b), (b'ALB1',n,7,(n+7+sum(addresses))&0xffffffff))
            self.assertEqual(list(struct.unpack_from('<'+'I'*n,b,16)),addresses)
        for addresses in [[],list(range(1,66)),[1,1],[0],[-1],[0x100000000]]:
            with self.assertRaises(ValueError):encode_catalog(addresses,7)

    def test_bmp_declared_length(self):
        b=bytearray(921654);b[:2]=b'BM'
        struct.pack_into('<I',b,2,len(b));struct.pack_into('<I',b,10,54)
        struct.pack_into('<IiiHHI',b,14,40,640,480,1,24,0)
        validate_bmp(b)
        struct.pack_into('<I',b,2,1)
        with self.assertRaises(ValueError):validate_bmp(b)

if __name__=='__main__':unittest.main()
