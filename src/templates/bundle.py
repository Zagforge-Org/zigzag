#!/usr/bin/env python3
"""
Bundle src/templates/src/ source files into the self-contained src/templates/dashboard.html.

Injection markers in template.html:
  <!-- @inject: file.css -->        → <style>content</style>
  <!-- @inject: file.js -->         → <script>content</script>
  <!-- @inject-text: file.js as id --> → <script type="text/plain" id="id">content</script>
"""

import re
from pathlib import Path

TEMPLATES_DIR = Path(__file__).parent
DEFAULT_TEMPLATE = TEMPLATES_DIR / "src" / "template.html"
DEFAULT_SRC_DIR  = TEMPLATES_DIR / "src"
DEFAULT_OUTPUT   = TEMPLATES_DIR / "dashboard.html"


def _inject(src_dir: Path, m: re.Match) -> str:
    directive = m.group(1)   # "file.css" or "file.js as id"
    text_mode = m.group(0).startswith("<!-- @inject-text:")

    if text_mode:
        # <!-- @inject-text: worker.js as hw-src -->
        parts = directive.split(" as ")
        filename = parts[0].strip()
        elem_id  = parts[1].strip() if len(parts) > 1 else "injected"
        path = src_dir / filename
        if not path.exists():
            raise SystemExit(f"bundle.py: missing source file: {path}")
        content  = path.read_text(encoding="utf-8")
        return f'<script type="text/plain" id="{elem_id}">\n{content}\n</script>'

    filename = directive.strip()
    path = src_dir / filename
    if not path.exists():
        raise SystemExit(f"bundle.py: missing source file: {path}")
    content  = path.read_text(encoding="utf-8")
    ext      = Path(filename).suffix.lower()

    if ext == ".css":
        return f"<style>\n{content}\n</style>"
    if ext == ".js":
        return f"<script>\n{content}\n</script>"
    return content  # passthrough for .html fragments


def bundle(
    template_path: Path = DEFAULT_TEMPLATE,
    src_dir: Path = DEFAULT_SRC_DIR,
    output_path: Path = DEFAULT_OUTPUT,
) -> None:
    template = template_path.read_text(encoding="utf-8")

    pattern = re.compile(
        r'<!-- @inject(?:-text)?:\s*(.*?)\s*-->'
    )
    result = pattern.sub(lambda m: _inject(src_dir, m), template)
    output_path.write_text(result, encoding="utf-8")
    print(f"Bundled {template_path} → {output_path} ({len(result):,} bytes)")


if __name__ == "__main__":
    bundle()
