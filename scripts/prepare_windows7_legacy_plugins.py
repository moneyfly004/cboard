#!/usr/bin/env python3
"""Remove Windows plugins that hard-require newer Windows APIs from a legacy build.

Flutter regenerates the Windows plugin files during `flutter pub get`. The
Windows 7 CI package runs this script after `pub get` and before
`flutter build windows --no-pub`, so the normal Windows package still uses the
full plugin set while the legacy package avoids loader-incompatible DLLs.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LEGACY_BLOCKED_PLUGINS = {
    "share_plus": {
        "cmake_entry": "share_plus",
        "include_pattern": re.compile(
            r"^#include <share_plus/share_plus_windows_plugin_c_api\.h>\r?\n",
            re.MULTILINE,
        ),
        "register_pattern": re.compile(
            r"^  SharePlusWindowsPluginCApiRegisterWithRegistrar\(\r?\n"
            r"      registry->GetRegistrarForPlugin\(\"SharePlusWindowsPluginCApi\"\)\);\r?\n",
            re.MULTILINE,
        ),
    },
}


def replace_optional(text: str, pattern: re.Pattern[str], replacement: str, label: str) -> str:
    text, count = pattern.subn(replacement, text)
    if count > 1:
        raise ValueError(f"expected at most one {label}, found {count}")
    return text


def remove_cmake_plugin(cmake_path: Path, plugin: str) -> None:
    text = cmake_path.read_text(encoding="utf-8")
    pattern = re.compile(rf"^  {re.escape(plugin)}\r?\n", re.MULTILINE)
    updated = replace_optional(text, pattern, "", f"{plugin} CMake plugin entry")
    cmake_path.write_text(updated, encoding="utf-8")


def remove_registrant_plugin(registrant_path: Path, plugin: dict[str, object]) -> None:
    text = registrant_path.read_text(encoding="utf-8")
    text = replace_optional(
        text,
        plugin["include_pattern"],  # type: ignore[arg-type]
        "",
        "share_plus include",
    )
    text = replace_optional(
        text,
        plugin["register_pattern"],  # type: ignore[arg-type]
        "",
        "share_plus registration block",
    )
    registrant_path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--windows-dir",
        type=Path,
        default=Path("windows"),
        help="Path to the Flutter Windows project directory.",
    )
    args = parser.parse_args()

    windows_dir = args.windows_dir
    cmake_path = windows_dir / "flutter" / "generated_plugins.cmake"
    registrant_path = windows_dir / "flutter" / "generated_plugin_registrant.cc"

    missing = [str(path) for path in (cmake_path, registrant_path) if not path.is_file()]
    if missing:
        print("Missing generated Windows plugin files:", ", ".join(missing), file=sys.stderr)
        return 1

    for plugin_name, plugin in LEGACY_BLOCKED_PLUGINS.items():
        remove_cmake_plugin(cmake_path, plugin["cmake_entry"])  # type: ignore[arg-type]
        remove_registrant_plugin(registrant_path, plugin)
        print(f"Removed {plugin_name} from Windows 7 legacy plugin registration.")

    combined = "\n".join(
        [
            cmake_path.read_text(encoding="utf-8"),
            registrant_path.read_text(encoding="utf-8"),
        ]
    )
    blocked_tokens = ["share_plus", "SharePlusWindowsPluginCApi"]
    remaining = [token for token in blocked_tokens if token in combined]
    if remaining:
        print(
            "Blocked Windows 7 plugin tokens remain: " + ", ".join(remaining),
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
