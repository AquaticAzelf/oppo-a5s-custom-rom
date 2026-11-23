"""Regression tests for the repo hygiene / script fixes.

Run with:  python -m unittest discover -s tests -v
"""

import ast
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Built from parts so the old name does not appear literally in any tracked file.
OLD_NAME = "oppo-a5s-" + "custom-rom"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


class StageBitgTests(unittest.TestCase):
    def test_root_is_assigned_at_runtime(self):
        tree = ast.parse(read("scripts/stage-bitg.py"))
        assigned = {
            t.id
            for node in tree.body
            if isinstance(node, ast.Assign)
            for t in node.targets
            if isinstance(t, ast.Name)
        }
        self.assertIn("ROOT", assigned)

    def test_docstring_has_no_slash_n_typo(self):
        doc = ast.get_docstring(ast.parse(read("scripts/stage-bitg.py"))) or ""
        self.assertNotIn("/n", doc)


class InstallFixTests(unittest.TestCase):
    def test_adb_resolved_from_path(self):
        text = read("scripts/install-fix.bat")
        self.assertIsNone(re.search(r"[A-Za-z]:\\", text), "hardcoded drive path")
        self.assertIn('set "ADB=adb"', text)

    def test_mkdir_precedes_first_push(self):
        text = read("scripts/install-fix.bat")
        self.assertLess(
            text.index("mkdir -p /data/adb/post-fs-data.d"),
            text.index("%ADB% push"),
        )

    def test_fix_pushed_once(self):
        text = read("scripts/install-fix.bat")
        self.assertEqual(text.count('%ADB% push "%~dp0fix.sh"'), 1)

    def test_perf_tune_is_installed_and_documented(self):
        text = read("scripts/install-fix.bat")
        self.assertIn(
            '%ADB% push "%~dp0perf-tune.sh" /data/adb/post-fs-data.d/20-perf.sh',
            text,
        )
        self.assertIn("perf-tune.sh", read("docs/FLASH-GUIDE.md"))


class VerifyImageTests(unittest.TestCase):
    def test_no_stale_v3_image_name(self):
        self.assertNotIn("los-custom-v3.img", read("scripts/verify-image.sh"))

    def test_no_machine_specific_mount_paths(self):
        text = read("scripts/verify-image.sh")
        self.assertNotIn("/root/verify.img", text)
        self.assertNotIn("/mnt/verify", text)

    def test_phh_secure_is_not_required(self):
        text = read("scripts/verify-image.sh")
        self.assertNotIn("phh/secure", text)
        self.assertIn("must EXIST", text)

    def test_size_gate_aborts_on_mismatch(self):
        text = read("scripts/verify-image.sh")
        self.assertIn('EXPECTED_SYSTEM_SIZE="${EXPECTED_SYSTEM_SIZE:-1900544000}"', text)
        self.assertIn('[ "$ACTUAL_SIZE" = "$EXPECTED_SYSTEM_SIZE" ]', text)
        self.assertIn("exit 1", text)


class GitignoreTests(unittest.TestCase):
    def test_release_archives_are_ignored(self):
        lines = read(".gitignore").splitlines()
        self.assertIn("*.gz", lines)
        self.assertIn("*.zip", lines)


class LegacyDecoderTests(unittest.TestCase):
    def test_legacy_build_is_marked(self):
        self.assertIn("LEGACY", read("scripts/build-xaac.sh"))

    def test_module_zip_matches_module_version(self):
        text = read("scripts/xaac-package.py")
        self.assertIn("xhe_aac_codec_v6.zip", text)
        self.assertIn("version=v6", text)


class KernelDocTests(unittest.TestCase):
    def test_grep_expectation_matches_snippet(self):
        text = read("docs/KERNEL.md")
        self.assertIn("Three lines should match", text)
        self.assertNotIn("Four lines should match", text)


class FlashOneTests(unittest.TestCase):
    def test_guard_order_in_code_matches_header(self):
        text = read("scripts/flash-one.sh")
        positions = [
            text.index("# --- guard 1: allow-list ---"),
            text.index("# --- guard 2: checksum sidecar ---"),
            text.index("# --- guard 3: size sanity ---"),
        ]
        self.assertEqual(positions, sorted(positions))
        header = [
            text.index("1. the partition must be on the allow-list"),
            text.index("2. a checksum sidecar"),
            text.index("3. a size sanity check"),
        ]
        self.assertEqual(header, sorted(header))


class ReleaseSumsTests(unittest.TestCase):
    def test_v71_entries_match_published_assets(self):
        text = read("release/SHA256SUMS.txt")
        self.assertIn("los-custom-v7.1.7z", text)
        self.assertNotIn("los-custom-v7.7z", text)
        self.assertIn(
            "c2bb0f0517444cc0f17db730070699f780b3121d83d7c3125e5a4cf1a2dd555e",
            text,
        )
        self.assertIn(
            "67a04e6525c324033eca52a9322973058975dd3c42e16666d9b457f3dd950813",
            text,
        )


class RenameTests(unittest.TestCase):
    def test_old_repo_name_is_gone_from_every_text_file(self):
        suffixes = {".md", ".html", ".txt", ".sh", ".py", ".bat"}
        offenders = []
        for path in ROOT.rglob("*"):
            if not path.is_file() or ".git" in path.parts:
                continue
            if path.suffix.lower() not in suffixes:
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            if OLD_NAME in text:
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [], "old repo name remains in: " + ", ".join(offenders))


class BuildImageTests(unittest.TestCase):
    def test_published_size_is_a_build_gate(self):
        text = read("scripts/build-image.sh")
        self.assertIn('EXPECTED_SYSTEM_SIZE="${EXPECTED_SYSTEM_SIZE:-1900544000}"', text)
        self.assertIn('[ "$FINAL_SIZE" = "$EXPECTED_SYSTEM_SIZE" ]', text)
        self.assertIn("exit 1", text)


if __name__ == "__main__":
    unittest.main()
