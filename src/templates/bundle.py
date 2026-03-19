#!/usr/bin/env python3
"""
Bundle src/templates/src/ source files into the self-contained src/templates/dashboard.html.

Build pipeline (run automatically when invoked as __main__):
  1. npm install  (skipped if node_modules already exists)
  2. esbuild src/main.ts          → dist/bundle.js
  3. esbuild src/highlight.worker.ts → dist/highlight.worker.js
  4. esbuild src/combined.ts      → dist/combined.js
  5. Python injection pass        → dashboard.html
  6. Python injection pass        → combined-dashboard.html

Injection markers in template.html:
  <!-- @inject: file.css -->            → <style>content</style>
  <!-- @inject: file.js -->             → <script>content</script>
  <!-- @inject-text: file.js as id -->  → <script type="text/plain" id="id">content</script>

Paths without a directory component are resolved relative to src_dir.
Paths with a directory component (e.g. dist/bundle.js) are resolved
relative to templates_dir.
"""

import re
import subprocess
import sys
from pathlib import Path

TEMPLATES_DIR = Path(__file__).parent
DEFAULT_TEMPLATE = TEMPLATES_DIR / "src" / "template.html"
DEFAULT_SRC_DIR  = TEMPLATES_DIR / "src"
DEFAULT_OUTPUT   = TEMPLATES_DIR / "dashboard.html"


def _resolve_path(filename: str, src_dir: Path, templates_dir: Path) -> Path:
    """Resolve an inject filename to an absolute path.

    Simple filenames (no directory separator) resolve relative to src_dir.
    Filenames with a directory component resolve relative to templates_dir
    (e.g. 'dist/bundle.js' → templates_dir/dist/bundle.js).
    """
    if "/" in filename or "\\" in filename:
        return templates_dir / filename
    return src_dir / filename


def _inject(src_dir: Path, templates_dir: Path, m: re.Match) -> str:
    directive = m.group(1)   # "file.css" or "file.js as id"
    text_mode = m.group(0).startswith("<!-- @inject-text:")

    if text_mode:
        # <!-- @inject-text: worker.js as hw-src -->
        parts = directive.split(" as ")
        filename = parts[0].strip()
        elem_id  = parts[1].strip() if len(parts) > 1 else "injected"
        path = _resolve_path(filename, src_dir, templates_dir)
        if not path.exists():
            raise SystemExit(f"bundle.py: missing source file: {path}")
        content  = path.read_text(encoding="utf-8")
        return f'<script type="text/plain" id="{elem_id}">\n{content}\n</script>'

    filename = directive.strip()
    path = _resolve_path(filename, src_dir, templates_dir)
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
    templates_dir: Path = TEMPLATES_DIR,
) -> None:
    template = template_path.read_text(encoding="utf-8")

    pattern = re.compile(
        r'<!-- @inject(?:-text)?:\s*(.*?)\s*-->'
    )
    result = pattern.sub(lambda m: _inject(src_dir, templates_dir, m), template)
    output_path.write_text(result, encoding="utf-8")
    print(f"Bundled {template_path} -> {output_path} ({len(result):,} bytes)")


def _esbuild_bin() -> str:
    """Return the platform-appropriate esbuild binary path."""
    bin_dir = TEMPLATES_DIR / "node_modules" / ".bin"
    cmd_path = bin_dir / "esbuild.cmd"   # Windows wrapper
    if cmd_path.exists():
        return str(cmd_path)
    return str(bin_dir / "esbuild")


def run_esbuild() -> None:
    """Run npm install (if needed) then esbuild to produce dist/bundle.js and
    dist/highlight.worker.js from their TypeScript sources."""
    node_modules = TEMPLATES_DIR / "node_modules"
    if not node_modules.exists() or not Path(_esbuild_bin()).exists():
        print("bundle.py: node_modules not found, running npm install...")
        subprocess.run(
            ["npm", "install"],
            cwd=TEMPLATES_DIR,
            check=True,
            shell=(sys.platform == "win32"),
        )

    dist_dir = TEMPLATES_DIR / "dist"
    dist_dir.mkdir(exist_ok=True)

    esbuild_common = [
        "--bundle",
        "--format=iife",
        "--target=es2020",
    ]

    print("bundle.py: building dist/bundle.js...")
    subprocess.run(
        [
            _esbuild_bin(),
            str(TEMPLATES_DIR / "src" / "main.ts"),
            *esbuild_common,
            f"--outfile={dist_dir / 'bundle.js'}",
        ],
        cwd=TEMPLATES_DIR,
        check=True,
    )

    # Prepend the disableWorkerMessageHandler flag so it runs before Prism
    # initialises inside the IIFE, preventing a duplicate message handler.
    print("bundle.py: building dist/highlight.worker.js...")
    subprocess.run(
        [
            _esbuild_bin(),
            str(TEMPLATES_DIR / "src" / "highlight.worker.ts"),
            *esbuild_common,
            "--banner:js=self.Prism={disableWorkerMessageHandler:true};",
            f"--outfile={dist_dir / 'highlight.worker.js'}",
        ],
        cwd=TEMPLATES_DIR,
        check=True,
    )

    print("bundle.py: building dist/combined.js...")
    subprocess.run(
        [
            _esbuild_bin(),
            str(TEMPLATES_DIR / "src" / "combined.ts"),
            *esbuild_common,
            f"--outfile={dist_dir / 'combined.js'}",
        ],
        cwd=TEMPLATES_DIR,
        check=True,
    )


if __name__ == "__main__":
    run_esbuild()
    bundle()
    bundle(
        template_path=TEMPLATES_DIR / "src" / "combined.html",
        src_dir=TEMPLATES_DIR / "src",
        output_path=TEMPLATES_DIR / "combined-dashboard.html",
        templates_dir=TEMPLATES_DIR,
    )
