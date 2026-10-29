"""Check dependency-notice omissions using isolated copies; no build or download."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("apk_notices", ROOT / "scripts/check-apk-notices.py")
NOTICES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NOTICES)


class NativeNoticesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="after-you-notice-test-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        for path in ["native/plugin/gradle.lockfile", "game/assets/licenses/native-components.txt", "game/assets/licenses/native-notices.txt", *NOTICES.APP_LICENSE_PARTS, NOTICES.APP_LICENSE]:
            target = self.repo / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / path, target)

    def test_current_full_inventory(self):
        self.assertEqual([], NOTICES.native_inventory_errors(self.repo))

    def test_missing_fcm_cannot_pass_exact_packaged_bytes_only(self):
        target = self.repo / "game/assets/licenses/native-components.txt"
        target.write_text(target.read_text(encoding="utf-8").replace("com.google.firebase:firebase-messaging:25.1.3", "omitted-fcm"), encoding="utf-8")
        self.assertTrue(any("firebase-messaging" in error for error in NOTICES.native_inventory_errors(self.repo)))

    def test_app_license_matches_repository_licenses(self):
        self.assertEqual([], NOTICES.app_license_errors(self.repo))
        app = (self.repo / NOTICES.APP_LICENSE).read_text(encoding="utf-8").replace("\r\n", "\n")
        self.assertTrue(app.startswith("After You\nCopyright (c) 2026 Aamir Abdul Azeez (https://aamirazeez.com)\n"))
        self.assertIn("AGPL-3.0-only", app)
        self.assertIn("GNU AFFERO GENERAL PUBLIC LICENSE", app)
        self.assertIn("All rights reserved.", app)
        self.assertNotIn("PolyForm", app)

    def test_stale_app_license_is_rejected(self):
        for part in NOTICES.APP_LICENSE_PARTS:
            with self.subTest(part=part):
                target = self.repo / part
                original = target.read_bytes()
                target.write_text(target.read_text(encoding="utf-8") + "\nA later change.\n", encoding="utf-8")
                self.assertTrue(NOTICES.app_license_errors(self.repo))
                target.write_bytes(original)
        (self.repo / "COPYRIGHT").unlink()
        self.assertTrue(NOTICES.app_license_errors(self.repo))

    def test_missing_runtime_lock_is_rejected(self):
        (self.repo / "native/plugin/gradle.lockfile").write_text("# Empty lock\n", encoding="utf-8")
        self.assertIn("No pinned native runtime dependencies found.", NOTICES.native_inventory_errors(self.repo))

    def test_truncated_upstream_protobuf_license_is_rejected(self):
        target = self.repo / "game/assets/licenses/native-notices.txt"
        target.write_text(target.read_text(encoding="utf-8").replace("Redistribution and use in source and binary forms, with or without", "Altered"), encoding="utf-8")
        self.assertTrue(any("protobuf-lite" in error for error in NOTICES.native_inventory_errors(self.repo)))


if __name__ == "__main__":
    unittest.main()
