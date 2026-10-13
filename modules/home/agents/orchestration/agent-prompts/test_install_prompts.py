from pathlib import Path
import tempfile
import unittest

from install_prompts import install


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source.md'
        self.source.write_text('# Shared instructions\n')
        self.canonical = self.root / 'config/agent-prompts/AGENTS.md'
        self.personal = self.root / 'config/profiles/personal/AGENTS.md'
        self.work = self.root / 'config/profiles/work/AGENTS.md'
        self.alias = self.root / 'custom client/AGENTS.override.md'
        self.manifest = {
            'source': str(self.source),
            'files': [str(self.canonical), str(self.personal), str(self.work)],
            'aliases': {str(self.alias): str(self.canonical)},
            'backup_dir': str(self.root / 'state/backups'),
        }

    def test_first_install_identical_profiles_and_permissions(self):
        self.assertEqual(len(install(self.manifest)), 4)
        for path in [self.canonical, self.personal, self.work, self.alias]:
            self.assertEqual(path.read_bytes(), self.source.read_bytes())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertTrue(self.alias.is_symlink())

    def test_repeated_activation_is_noop(self):
        install(self.manifest)
        before = self.canonical.stat().st_mtime_ns
        self.assertEqual(install(self.manifest), [])
        self.assertEqual(self.canonical.stat().st_mtime_ns, before)

    def test_revision_update_and_rollback(self):
        install(self.manifest)
        self.source.write_text('# Revised\n')
        install(self.manifest)
        self.assertEqual(self.alias.read_text(), '# Revised\n')
        self.source.write_text('# Shared instructions\n')
        install(self.manifest)
        self.assertEqual(self.alias.read_text(), self.source.read_text())

    def test_existing_local_edits_are_backed_up(self):
        self.alias.parent.mkdir(parents=True)
        self.alias.write_text('local edits')
        install(self.manifest)
        backups = list(Path(self.manifest['backup_dir']).rglob('*.md'))
        self.assertEqual([path.read_text() for path in backups], ['local edits'])
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)

    def test_old_store_symlink_is_replaced_without_modifying_target(self):
        old = self.root / 'old.md'
        old.write_text('previous instructions')
        self.alias.parent.mkdir()
        self.alias.symlink_to(old)
        install(self.manifest)
        self.assertEqual(old.read_text(), 'previous instructions')
        self.assertEqual(self.alias.read_text(), self.source.read_text())

    def test_profile_canonical_symlink_is_replaced(self):
        self.personal.parent.mkdir(parents=True)
        self.personal.symlink_to(self.source)
        install(self.manifest)
        self.assertFalse(self.personal.is_symlink())

    def test_dangling_alias_is_repaired(self):
        self.alias.parent.mkdir()
        self.alias.symlink_to(self.root / 'absent')
        install(self.manifest)
        self.assertEqual(self.alias.read_text(), self.source.read_text())

    def test_conflict_preflight_leaves_all_files_unchanged(self):
        install(self.manifest)
        self.alias.unlink()
        self.alias.mkdir()
        self.source.write_text('# Changed\n')
        with self.assertRaises(ValueError):
            install(self.manifest)
        self.assertEqual(self.canonical.read_text(), '# Shared instructions\n')

    def test_missing_source_creates_nothing(self):
        self.source.unlink()
        with self.assertRaises(FileNotFoundError):
            install(self.manifest)
        self.assertFalse(self.canonical.parent.exists())

    def test_invalid_sources_create_nothing(self):
        for content in [b'', b' ', b'\xff', b'bad\x00']:
            self.source.write_bytes(content)
            with self.subTest(content=content), self.assertRaises(ValueError):
                install(self.manifest)
            self.assertFalse(self.canonical.exists())

    def test_dry_run_does_not_create_files(self):
        self.assertEqual(len(install(self.manifest, dry_run=True)), 4)
        self.assertFalse(self.canonical.parent.exists())

    def test_custom_directory_symlink(self):
        target = self.root/'external-config'
        target.mkdir()
        self.alias.parent.symlink_to(target)
        install(self.manifest)
        self.assertEqual((target/self.alias.name).read_text(), self.source.read_text())

    def test_invalid_alias_target(self):
        self.manifest['aliases'][str(self.alias)] = str(self.root/'unknown')
        with self.assertRaises(ValueError):
            install(self.manifest)

    def test_overlapping_destinations(self):
        self.manifest['aliases'][str(self.canonical)] = str(self.canonical)
        with self.assertRaises(ValueError):
            install(self.manifest)

    def test_destination_parent_conflict(self):
        self.manifest['aliases'][str(self.canonical/'child')] = str(self.canonical)
        with self.assertRaises(ValueError):
            install(self.manifest)
        self.assertFalse(self.canonical.exists())

    def test_dangling_directory_symlink(self):
        self.alias.parent.symlink_to(self.root/'absent')
        with self.assertRaises(ValueError):
            install(self.manifest)
        self.assertFalse(self.canonical.exists())


if __name__ == '__main__':
    unittest.main()
