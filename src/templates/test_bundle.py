#!/usr/bin/env python3
"""Tests for bundle.py"""
import sys
import os
import unittest
import tempfile
import shutil
from pathlib import Path

# Add parent dir so we can import or run bundle directly
TEMPLATES_DIR = Path(__file__).parent

class TestBundler(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        (self.tmp / "src").mkdir()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def _run_bundle(self, template_content, src_files):
        """Write files to tmp dir and run bundle logic."""
        for name, content in src_files.items():
            (self.tmp / "src" / name).write_text(content)
        (self.tmp / "src" / "template.html").write_text(template_content)
        # Import bundle module and run with tmp paths
        import importlib.util
        spec = importlib.util.spec_from_file_location("bundle", TEMPLATES_DIR / "bundle.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        mod.bundle(
            template_path=self.tmp / "src" / "template.html",
            src_dir=self.tmp / "src",
            output_path=self.tmp / "dashboard.html",
        )
        return (self.tmp / "dashboard.html").read_text()

    def test_inject_css(self):
        result = self._run_bundle(
            "<!-- @inject: style.css -->",
            {"style.css": "body { color: red; }"},
        )
        self.assertIn("<style>", result)
        self.assertIn("body { color: red; }", result)
        self.assertIn("</style>", result)
        self.assertNotIn("<!-- @inject:", result)

    def test_inject_js(self):
        result = self._run_bundle(
            "<!-- @inject: app.js -->",
            {"app.js": "var x = 1;"},
        )
        self.assertIn("<script>", result)
        self.assertIn("var x = 1;", result)
        self.assertIn("</script>", result)

    def test_inject_text(self):
        result = self._run_bundle(
            '<!-- @inject-text: worker.js as hw-src -->',
            {"worker.js": "self.onmessage = function(){};"},
        )
        self.assertIn('id="hw-src"', result)
        self.assertIn('type="text/plain"', result)
        self.assertIn("self.onmessage = function(){};", result)

    def test_passthrough_zigzag_markers(self):
        """Zigzag injection markers must pass through unchanged."""
        result = self._run_bundle(
            "__ZIGZAG_DATA__ __ZIGZAG_CONTENT__",
            {},
        )
        self.assertIn("__ZIGZAG_DATA__", result)
        self.assertIn("__ZIGZAG_CONTENT__", result)

    def test_multiple_injections(self):
        result = self._run_bundle(
            "<!-- @inject: a.css -->\n<!-- @inject: b.js -->",
            {"a.css": ".a{}", "b.js": "var b;"},
        )
        self.assertIn("<style>", result)
        self.assertIn("<script>", result)

if __name__ == "__main__":
    unittest.main()
