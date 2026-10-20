import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "apply_port.py"
spec = importlib.util.spec_from_file_location("apply_port", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PatchPlanTests(unittest.TestCase):
    def test_source_drift_does_not_write_any_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            port, upstream = root / "port", root / "upstream"
            (port / "port/patches").mkdir(parents=True)
            upstream.mkdir()
            first = upstream / "first.swift"
            first.write_text("original")
            (upstream / "second.swift").write_text("unexpected")
            registry = [{"path": "first.swift", "old": "original", "new": "changed"},
                        {"path": "second.swift", "old": "expected baseline", "new": "changed"}]
            (port / "port/patches/changes.json").write_text(json.dumps(registry))
            with patch.object(module, "PORT", port), self.assertRaises(ValueError):
                module.plan_patches(upstream)
            self.assertEqual(first.read_text(), "original")

    def test_reapplying_import_insertion_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            port, upstream = root / "port", root / "upstream"
            (port / "port/patches").mkdir(parents=True)
            (port / "port/overlays").mkdir()
            upstream.mkdir()
            source = upstream / "test.swift"
            source.write_text("import Foundation\n")
            registry = [{"path": "test.swift", "old": "import Foundation\n",
                         "new": "import Foundation\nimport ExteraPreferences\n"}]
            (port / "port/patches/changes.json").write_text(json.dumps(registry))
            with patch.object(module, "PORT", port):
                planned = module.plan_patches(upstream)
                source.write_text(planned[source.resolve()])
                reapplied = module.plan_patches(upstream)
            self.assertEqual(reapplied[source.resolve()].count("import ExteraPreferences"), 1)

    def test_overlay_paths_cannot_escape_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                module.safe_path(Path(directory), "../outside")


if __name__ == "__main__":
    unittest.main()
