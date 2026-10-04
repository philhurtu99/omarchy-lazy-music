#!/usr/bin/env python3
"""Run real keyboard events against the plugin and installed Omarchy UI."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory(prefix="lazy-music-keyboard-") as temporary:
    work = Path(temporary)
    (work / "qs").symlink_to("/usr/share/omarchy/shell", target_is_directory=True)
    runtime = work / "runtime"
    runtime.mkdir(mode=0o700)
    environment = os.environ.copy()
    environment.pop("WAYLAND_DISPLAY", None)
    environment.update(
        QT_QPA_PLATFORM="offscreen",
        QT_QPA_PLATFORMTHEME="generic",
        QML_IMPORT_PATH=str(work),
        XDG_RUNTIME_DIR=str(runtime),
    )
    template = Path(__file__).with_name("shell.qml")
    harness = work / "shell.qml"
    harness.write_text(template.read_text().replace(
        'import "../" as Lazy', f'import "{template.parent.parent.as_uri()}" as Lazy'
    ))
    result = subprocess.run(
        ["qs", "--no-color", "-p", str(harness)],
        env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=45,
    )
    print(result.stdout, end="")
    sys.exit(0 if result.returncode == 0 and "KEYBOARD_TESTS_PASS" in result.stdout else 1)
