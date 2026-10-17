"""Filesystem-only restoration checks; no simulator, phone or firmware execution."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("benchmark_simulator", Path(__file__).resolve().parents[1] / "scripts/benchmark-simulator.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class AppStateRestoreTests(unittest.TestCase):
    def test_restores_unrelated_documents_and_preferences_after_container_moves(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            original = root / "original-container"
            files = {"Documents/Firmwares/saved.flash": b"\x00\xffsaved", "Documents/unrelated/note.txt": b"keep", "Library/Preferences/app.plist": b"selected firmware"}
            for name, content in files.items():
                path = original / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            backup = root / "backup"
            runner.backup_app_state(original, backup)
            relocated = root / "relocated-container"
            for name in ["Documents/Firmwares/saved.flash", "Documents/new-report.json", "Library/Preferences/added.plist"]:
                path = relocated / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"changed")
            runner.restore_app_state(relocated, backup)
            self.assertEqual({str(p.relative_to(relocated)): p.read_bytes() for p in relocated.rglob("*") if p.is_file()}, files)

    def test_restores_absence_of_documents_and_preferences(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            original = root / "original"
            original.mkdir()
            backup = root / "backup"
            runner.backup_app_state(original, backup)
            (original / "Documents").mkdir()
            (original / "Library/Preferences").mkdir(parents=True)
            (original / "Documents/generated.json").write_bytes(b"report")
            runner.restore_app_state(original, backup)
            self.assertFalse((original / "Documents").exists())
            self.assertFalse((original / "Library/Preferences").exists())
