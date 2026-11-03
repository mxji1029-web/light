"""File-level transaction tests; never access the real TF card."""
import importlib.util
import contextlib
import io
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

if importlib.util.find_spec('deploy_departure_album'):
    import deploy_departure_album as deploy
else:
    deploy = None


class DeploymentPresenceTest(unittest.TestCase):
    def test_deployment_tool_exists(self):
        self.assertIsNotNone(deploy, 'The departure deployment tool is not implemented')


@unittest.skipUnless(deploy, 'Deployment tool not yet implemented')
class DepartureDeploymentTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.card = Path(self.temp.name)
        self.index = self.card / 'LYRIC.IDX'
        self.index.write_bytes(b'A' * 512)
        self.other = self.card / 'KEEP.TXT'
        self.other.write_bytes(b'original resource')
        self.entry = dict(size=512, contiguous=True, first_sector=9000,
                          first_cluster=3, clusters=[3])
        self.files = {'lyric.idx': self.entry,
                      'keep.txt': dict(size=17, contiguous=True, first_sector=9050,
                                       first_cluster=4, clusters=[4])}
        self.before = {p.name: deploy.digest(p) for p in self.card.iterdir()}
        self.geometry = {'serial': deploy.EXPECTED_SERIAL, 'total_sectors': 62000000}
        self.card_patch = patch.object(deploy, 'CARD', self.card)
        self.card_patch.start()
        self.addCleanup(self.card_patch.stop)

    def test_valid_commit_preserves_other_file(self):
        with patch.object(deploy, 'snapshot', return_value=(self.files, self.geometry)), \
             patch.object(deploy, 'read_raw', return_value=b'B' * 512):
            deploy.commit_catalog(b'A' * 512, b'B' * 512, self.before, self.files)
        self.assertEqual(self.index.read_bytes(), b'B' * 512)
        self.assertEqual(self.other.read_bytes(), b'original resource')

    def test_external_index_update_is_not_overwritten(self):
        self.index.write_bytes(b'X' * 512)
        with patch.object(deploy, 'snapshot', return_value=(self.files, self.geometry)):
            with self.assertRaisesRegex(ValueError, 'changed'):
                deploy.commit_catalog(b'A' * 512, b'B' * 512, self.before, self.files)
        self.assertEqual(self.index.read_bytes(), b'X' * 512)

    def test_failed_readback_restores_original_index(self):
        with patch.object(deploy, 'snapshot', return_value=(self.files, self.geometry)), \
             patch.object(deploy, 'read_raw', side_effect=[b'wrong', b'A' * 512]):
            with self.assertRaisesRegex(IOError, 'readback'):
                deploy.commit_catalog(b'A' * 512, b'B' * 512, self.before, self.files)
        self.assertEqual(self.index.read_bytes(), b'A' * 512)
        self.assertEqual(self.other.read_bytes(), b'original resource')

    def test_moved_index_is_rejected_before_writing(self):
        moved = dict(self.files)
        moved['lyric.idx'] = dict(self.entry, first_sector=9100)
        with patch.object(deploy, 'snapshot', return_value=(moved, self.geometry)):
            with self.assertRaisesRegex(ValueError, 'allocation'):
                deploy.commit_catalog(b'A' * 512, b'B' * 512, self.before, self.files)
        self.assertEqual(self.index.read_bytes(), b'A' * 512)

    def test_story_order_has_22_unique_images_and_preserves_first_pair(self):
        expected = ([f'PIC{i:04d}.BMP' for i in range(1, 9)] +
                    ['DEP0001.BMP', 'PIC0009.BMP', 'DEP0002.BMP', 'DEP0003.BMP',
                     'DEP0004.BMP', 'PIC0010.BMP', 'FIX00011.BMP', 'FIX00012.BMP'] +
                    [f'FAM{i:04d}.BMP' for i in range(1, 7)])
        self.assertEqual(deploy.NAMES, expected)
        self.assertEqual(len(set(deploy.NAMES)), 22)
        self.assertEqual(deploy.NAMES[:2], deploy.OLD_NAMES[:2])

    def test_catalog_order_accepts_18_and_idempotent_22(self):
        files = {name.lower(): {'first_sector': 10000 + i * 2000}
                 for i, name in enumerate(deploy.NAMES)}
        files['lyric.pcm'] = {'first_sector': 100000}
        for names in (deploy.OLD_NAMES, deploy.NAMES):
            sectors = [files[n.lower()]['first_sector'] for n in names]
            payload = deploy.encode_catalog(sectors, 100000)
            self.assertEqual(deploy.validate_catalog_order(payload, files), len(names))

    def test_wrong_order_or_audio_pointer_is_rejected(self):
        files = {name.lower(): {'first_sector': 10000 + i * 2000}
                 for i, name in enumerate(deploy.NAMES)}
        files['lyric.pcm'] = {'first_sector': 100000}
        sectors = [files[n.lower()]['first_sector'] for n in deploy.OLD_NAMES]
        wrong = sectors.copy()
        wrong[0], wrong[1] = wrong[1], wrong[0]
        with self.assertRaisesRegex(ValueError, 'ordering'):
            deploy.validate_catalog_order(deploy.encode_catalog(wrong, 100000), files)
        with self.assertRaisesRegex(ValueError, 'audio'):
            deploy.validate_catalog_order(deploy.encode_catalog(sectors, 100001), files)

    def test_full_temporary_deployment_dry_run_apply_and_idempotence(self):
        project = self.card / 'project'
        folder = project / 'material/departure_story_20261023'
        pack = folder / 'board'
        pack.mkdir(parents=True)
        bmp = bytearray(921654)
        struct.pack_into('<2sIHHI', bmp, 0, b'BM', len(bmp), 0, 0, 54)
        struct.pack_into('<IiiHHI', bmp, 14, 40, 640, 480, 1, 24, 0)
        for name in deploy.OLD_NAMES:
            (self.card / name).write_bytes(bmp)
        for i, name in enumerate(deploy.ADDED):
            bmp[54] = i + 1
            (pack / name).write_bytes(bmp)
        (self.card / 'LYRIC.PCM').write_bytes(struct.pack('<4sIII', b'APCM', 48000, 4, 1) + b'\0' * 8)
        # Ensure backup metadata never overwrites a same-named original file.
        (self.card / 'manifest.json').write_bytes(b'original user manifest')
        ordered = ['LYRIC.IDX', 'LYRIC.PCM', 'KEEP.TXT', 'manifest.json'] + deploy.NAMES
        addresses = {name.lower(): 9000 + i * 4096 for i, name in enumerate(ordered)}
        initial = deploy.encode_catalog([addresses[n.lower()] for n in deploy.OLD_NAMES],
                                        addresses['lyric.pcm'])
        self.index.write_bytes(initial)
        geometry = dict(serial=deploy.EXPECTED_SERIAL, total_sectors=62000000,
                        cluster_bytes=32768, bps=512, spc=64)

        def fake_snapshot():
            layout = {}
            for path in self.card.iterdir():
                if path.is_file():
                    size = path.stat().st_size
                    sector = addresses[path.name.lower()]
                    cluster = 2 + (sector - 8192) // 64
                    layout[path.name.lower()] = dict(
                        first_sector=sector, size=size, contiguous=True,
                        first_cluster=cluster,
                        clusters=list(range(cluster, cluster + (size + 32767) // 32768)))
            return layout, geometry

        def fake_raw(entry, card_geometry):
            deploy.check_extent(entry, card_geometry)
            name = next(n for n, address in addresses.items() if address == entry['first_sector'])
            return (self.card / name).read_bytes()

        hashes_before = {p.name: deploy.digest(p) for p in self.card.iterdir() if p.is_file()}
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(deploy, 'ROOT', project))
            stack.enter_context(patch.object(deploy, 'FOLDER', folder))
            stack.enter_context(patch.object(deploy, 'PACK', pack))
            stack.enter_context(patch.object(deploy, 'EXPECTED_SAMPLES', 4))
            stack.enter_context(patch.object(deploy, 'snapshot', side_effect=fake_snapshot))
            stack.enter_context(patch.object(deploy, 'read_raw', side_effect=fake_raw))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            with patch('sys.argv', ['deploy_departure_album.py']):
                deploy.main()
            self.assertEqual(hashes_before, {p.name: deploy.digest(p) for p in self.card.iterdir() if p.is_file()})
            self.assertFalse((project / 'backups').exists())
            with patch('sys.argv', ['deploy_departure_album.py', '--apply']):
                deploy.main()
            layout, _ = fake_snapshot()
            self.assertEqual(deploy.validate_catalog_order(self.index.read_bytes(), layout), 22)
            backup = next((project / 'backups').iterdir())
            self.assertEqual((backup / 'files/manifest.json').read_bytes(), b'original user manifest')
            self.assertEqual((backup / 'files/LYRIC.IDX').read_bytes(), initial)
            for name, expected in hashes_before.items():
                if name.lower() != 'lyric.idx':
                    self.assertEqual(deploy.digest(self.card / name), expected)
            hashes_after = {p.name: deploy.digest(p) for p in self.card.iterdir() if p.is_file()}
            with patch('sys.argv', ['deploy_departure_album.py', '--apply']):
                deploy.main()
            self.assertEqual(hashes_after, {p.name: deploy.digest(p) for p in self.card.iterdir() if p.is_file()})
            self.assertEqual(len(list((project / 'backups').iterdir())), 1)
            reports = [json.loads(p.read_text(encoding='utf-8')) for p in folder.glob('deployment_*.json')]
            self.assertEqual({r['status'] for r in reports}, {'deployed_verified', 'already_deployed_verified'})


if __name__ == '__main__':
    unittest.main()
