"""Exercise index rollback on temporary files, never the actual TF card."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import deploy_family_album as deploy

class CatalogCommitTest(unittest.TestCase):
    def test_changed_index_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            card=Path(directory);index=card/'LYRIC.IDX'
            index.write_bytes(b'X'*512)
            with patch.object(deploy,'CARD',card):
                with self.assertRaisesRegex(ValueError,'changed'):
                    deploy.commit_catalog(b'A'*512,b'B'*512,{})
            self.assertEqual(index.read_bytes(),b'X'*512)

    def test_failed_readback_restores_original(self):
        with tempfile.TemporaryDirectory() as directory:
            card=Path(directory);index=card/'LYRIC.IDX';index.write_bytes(b'A'*512)
            files={'lyric.idx':{}}
            with patch.object(deploy,'CARD',card), patch.object(deploy,'snapshot',return_value=(files,{})), patch.object(deploy,'read_raw',side_effect=[b'wrong',b'A'*512]):
                with self.assertRaisesRegex(IOError,'readback'):
                    deploy.commit_catalog(b'A'*512,b'B'*512,{})
            self.assertEqual(index.read_bytes(),b'A'*512)

    def test_valid_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            card=Path(directory);index=card/'LYRIC.IDX';index.write_bytes(b'A'*512)
            with patch.object(deploy,'CARD',card), patch.object(deploy,'snapshot',return_value=({'lyric.idx':{}},{})), patch.object(deploy,'read_raw',return_value=b'B'*512):
                deploy.commit_catalog(b'A'*512,b'B'*512,{})
            self.assertEqual(index.read_bytes(),b'B'*512)

if __name__=='__main__':
    unittest.main()
