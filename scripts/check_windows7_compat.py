#!/usr/bin/env python3
"""Static Windows 7 compatibility checks for Windows release artifacts.

This is a gate for packaging a legacy Windows 7 build. It does not prove that
the app runs correctly on Windows 7; a real Windows 7 SP1 VM is still required
for runtime validation. It catches the common hard blockers that would prevent
the executable or bundled DLLs from loading at all.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


TARGET_WINDOWS_VERSION = (6, 1)
WINDOWS_7_SUPPORTED_OS_GUID = "{35138b9a-5d96-4fbd-8e2d-a2440225f93a}"

BLOCKED_DLLS = {
    "shcore.dll": "Windows 8.1+ system DLL; Windows 7 does not provide it",
    "dcomp.dll": "Windows 8+ DirectComposition DLL",
    "windows.ui.dll": "Windows 8+ system DLL",
}

BLOCKED_API_PREFIXES = {
    "api-ms-win-core-winrt-": "WinRT API-set import; Windows 7 cannot load it",
}

BLOCKED_IMPORTS = {
    "adjustwindowrectexfordpi": "Windows 10 1607+",
    "createdispatcherqueuecontroller": "Windows 10 1803+",
    "createfile2": "Windows 8+",
    "getdpiforsystem": "Windows 10 1607+",
    "getdpiforwindow": "Windows 10 1607+",
    "getoverlappedresultex": "Windows 8+",
    "getpackagefamilyname": "Windows 8+",
    "getprocessmitigationpolicy": "Windows 8+",
    "getsystemmetricsfordpi": "Windows 10 1607+",
    "getsystemtimepreciseasfiletime": "Windows 8+",
    "getthreaddescription": "Windows 10 1607+",
    "prefetchvirtualmemory": "Windows 8+",
    "setdefaultdlldirectories": "Windows 8+, or Windows 7 only with KB2533623",
    "setprocessdpiawareness": "Windows 8.1+",
    "setprocessdpiawarenesscontext": "Windows 10 1607+",
    "setprocessmitigationpolicy": "Windows 8+",
    "setthreaddescription": "Windows 10 1607+",
}


class PEFormatError(Exception):
    pass


@dataclass
class Section:
    name: str
    virtual_address: int
    virtual_size: int
    raw_address: int
    raw_size: int


@dataclass
class PEInfo:
    path: Path
    machine: str
    is_64_bit: bool
    subsystem_version: tuple[int, int]
    imports: dict[str, list[str]]


def read_u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def read_u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def read_u64(data: bytes, offset: int) -> int:
    return struct.unpack_from("<Q", data, offset)[0]


def read_c_string(data: bytes, offset: int) -> str:
    if offset < 0 or offset >= len(data):
        raise PEFormatError(f"string offset out of range: 0x{offset:x}")
    end = data.find(b"\0", offset)
    if end == -1:
        raise PEFormatError(f"unterminated string at offset 0x{offset:x}")
    return data[offset:end].decode("ascii", errors="replace")


def machine_name(machine: int) -> str:
    return {
        0x014C: "x86",
        0x8664: "x64",
        0xAA64: "arm64",
    }.get(machine, f"0x{machine:04x}")


def parse_pe(path: Path) -> PEInfo:
    data = path.read_bytes()
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise PEFormatError("missing MZ header")

    pe_offset = read_u32(data, 0x3C)
    if pe_offset + 24 >= len(data) or data[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise PEFormatError("missing PE header")

    coff_offset = pe_offset + 4
    (
        machine,
        section_count,
        _timestamp,
        _symbol_table,
        _symbol_count,
        optional_header_size,
        _characteristics,
    ) = struct.unpack_from("<HHIIIHH", data, coff_offset)

    optional_offset = coff_offset + 20
    optional_magic = read_u16(data, optional_offset)
    if optional_magic == 0x20B:
        is_64_bit = True
        data_directory_offset = 112
        thunk_size = 8
        ordinal_mask = 0x8000000000000000
    elif optional_magic == 0x10B:
        is_64_bit = False
        data_directory_offset = 96
        thunk_size = 4
        ordinal_mask = 0x80000000
    else:
        raise PEFormatError(f"unsupported optional header magic: 0x{optional_magic:x}")

    subsystem_version = (
        read_u16(data, optional_offset + 48),
        read_u16(data, optional_offset + 50),
    )

    section_offset = optional_offset + optional_header_size
    sections: list[Section] = []
    for index in range(section_count):
        offset = section_offset + index * 40
        if offset + 40 > len(data):
            raise PEFormatError("section header outside file")
        name = data[offset : offset + 8].split(b"\0", 1)[0].decode("ascii", "replace")
        virtual_size = read_u32(data, offset + 8)
        virtual_address = read_u32(data, offset + 12)
        raw_size = read_u32(data, offset + 16)
        raw_address = read_u32(data, offset + 20)
        sections.append(
            Section(
                name=name,
                virtual_address=virtual_address,
                virtual_size=virtual_size,
                raw_address=raw_address,
                raw_size=raw_size,
            )
        )

    def rva_to_offset(rva: int) -> int:
        for section in sections:
            size = max(section.virtual_size, section.raw_size)
            if section.virtual_address <= rva < section.virtual_address + size:
                delta = rva - section.virtual_address
                if delta >= section.raw_size and section.raw_size != 0:
                    raise PEFormatError(f"RVA 0x{rva:x} points past raw section data")
                return section.raw_address + delta
        # Some directories can point into the headers.
        if 0 <= rva < section_offset:
            return rva
        raise PEFormatError(f"cannot map RVA 0x{rva:x}")

    imports: dict[str, list[str]] = {}
    import_directory_entry = optional_offset + data_directory_offset + 8
    if import_directory_entry + 8 <= optional_offset + optional_header_size:
        import_rva = read_u32(data, import_directory_entry)
        if import_rva:
            descriptor_offset = rva_to_offset(import_rva)
            while True:
                if descriptor_offset + 20 > len(data):
                    raise PEFormatError("import descriptor outside file")
                original_first_thunk = read_u32(data, descriptor_offset)
                name_rva = read_u32(data, descriptor_offset + 12)
                first_thunk = read_u32(data, descriptor_offset + 16)
                if original_first_thunk == 0 and name_rva == 0 and first_thunk == 0:
                    break

                dll_name = read_c_string(data, rva_to_offset(name_rva)).lower()
                thunk_rva = original_first_thunk or first_thunk
                thunk_offset = rva_to_offset(thunk_rva)
                functions: list[str] = []
                while True:
                    thunk_value = (
                        read_u64(data, thunk_offset)
                        if thunk_size == 8
                        else read_u32(data, thunk_offset)
                    )
                    if thunk_value == 0:
                        break
                    if thunk_value & ordinal_mask:
                        functions.append(f"ordinal:{thunk_value & 0xFFFF}")
                    else:
                        hint_name_offset = rva_to_offset(thunk_value)
                        functions.append(read_c_string(data, hint_name_offset + 2))
                    thunk_offset += thunk_size
                imports[dll_name] = sorted(set(functions), key=str.lower)
                descriptor_offset += 20

    return PEInfo(
        path=path,
        machine=machine_name(machine),
        is_64_bit=is_64_bit,
        subsystem_version=subsystem_version,
        imports=imports,
    )


def parse_version(value: str) -> tuple[int, int]:
    match = re.match(r"^\s*(\d+)(?:\.(\d+))?", value)
    if not match:
        raise argparse.ArgumentTypeError(f"invalid version: {value}")
    return int(match.group(1)), int(match.group(2) or "0")


def collect_pe_files(release_dir: Path) -> list[Path]:
    return sorted(
        [
            path
            for path in release_dir.rglob("*")
            if path.is_file() and path.suffix.lower() in {".exe", ".dll"}
        ]
    )


def markdown_report(report: dict) -> str:
    status = "PASS" if report["compatible"] else "FAIL"
    lines = [
        f"# Windows 7 Compatibility Report",
        "",
        f"Status: **{status}**",
        "",
        f"Target: Windows 7 SP1 x64 ({TARGET_WINDOWS_VERSION[0]}.{TARGET_WINDOWS_VERSION[1]})",
        f"Release directory: `{report['release_dir']}`",
        "",
    ]

    if report["blockers"]:
        lines.extend(["## Blockers", ""])
        for blocker in report["blockers"]:
            lines.append(f"- {blocker}")
        lines.append("")

    if report["warnings"]:
        lines.extend(["## Warnings", ""])
        for warning in report["warnings"]:
            lines.append(f"- {warning}")
        lines.append("")

    lines.extend(["## PE Files", ""])
    for pe in report["pe_files"]:
        lines.append(
            "- `{path}`: machine={machine}, subsystem={major}.{minor}, imports={imports}".format(
                path=pe["path"],
                machine=pe["machine"],
                major=pe["subsystem_version"][0],
                minor=pe["subsystem_version"][1],
                imports=pe["imported_dll_count"],
            )
        )

    lines.extend(
        [
            "",
            "## Notes",
            "",
            "- This is a static loader-compatibility gate, not a runtime test.",
            "- A release can only be called Windows 7 compatible after this report passes and the app is started in a real Windows 7 SP1 VM.",
        ]
    )
    return "\n".join(lines) + "\n"


def add_blocked_imports(info: PEInfo, blockers: list[str]) -> None:
    relative = info.path.as_posix()
    for dll_name, functions in info.imports.items():
        dll_lower = dll_name.lower()
        if dll_lower in BLOCKED_DLLS:
            blockers.append(f"{relative} imports {dll_name}: {BLOCKED_DLLS[dll_lower]}")
        for prefix, reason in BLOCKED_API_PREFIXES.items():
            if dll_lower.startswith(prefix):
                blockers.append(f"{relative} imports {dll_name}: {reason}")
        for function in functions:
            reason = BLOCKED_IMPORTS.get(function.lower())
            if reason:
                blockers.append(f"{relative} imports {function} from {dll_name}: {reason}")


def analyze(args: argparse.Namespace) -> dict:
    release_dir = args.release_dir.resolve()
    blockers: list[str] = []
    warnings: list[str] = []

    if not release_dir.is_dir():
        blockers.append(f"release directory does not exist: {release_dir}")
        pe_paths: list[Path] = []
    else:
        pe_paths = collect_pe_files(release_dir)
        if not pe_paths:
            blockers.append(f"no .exe or .dll files found in {release_dir}")

    pe_reports: list[dict] = []
    for path in pe_paths:
        relative_path = path.relative_to(release_dir)
        try:
            info = parse_pe(path)
        except PEFormatError as exc:
            blockers.append(f"{relative_path.as_posix()} is not a readable PE file: {exc}")
            continue

        if info.machine != "x64":
            blockers.append(f"{relative_path.as_posix()} is {info.machine}; Windows 7 package expects x64")
        if info.subsystem_version > TARGET_WINDOWS_VERSION:
            blockers.append(
                "{path} subsystem version is {major}.{minor}; Windows 7 loader target is 6.1".format(
                    path=relative_path.as_posix(),
                    major=info.subsystem_version[0],
                    minor=info.subsystem_version[1],
                )
            )
        add_blocked_imports(
            PEInfo(
                path=relative_path,
                machine=info.machine,
                is_64_bit=info.is_64_bit,
                subsystem_version=info.subsystem_version,
                imports=info.imports,
            ),
            blockers,
        )
        pe_reports.append(
            {
                "path": relative_path.as_posix(),
                "machine": info.machine,
                "is_64_bit": info.is_64_bit,
                "subsystem_version": list(info.subsystem_version),
                "imported_dll_count": len(info.imports),
            }
        )

    if args.manifest:
        manifest_path = args.manifest.resolve()
        if not manifest_path.is_file():
            blockers.append(f"manifest file does not exist: {manifest_path}")
        else:
            manifest = manifest_path.read_text(encoding="utf-8", errors="replace").lower()
            if WINDOWS_7_SUPPORTED_OS_GUID not in manifest:
                blockers.append(
                    f"{args.manifest} does not declare the Windows 7 supportedOS GUID "
                    f"{WINDOWS_7_SUPPORTED_OS_GUID}"
                )

    if args.installer_min_version:
        installer_version = parse_version(args.installer_min_version)
        if installer_version > TARGET_WINDOWS_VERSION:
            blockers.append(
                "installer MinVersion is {actual}; Windows 7 SP1 requires 6.1 or lower".format(
                    actual=args.installer_min_version
                )
            )

    if args.flutter_version:
        warnings.append(
            "Flutter version {version} still needs official/runtime validation for Windows 7. "
            "Current Flutter desktop releases are documented for Windows 10/11, so static PE checks alone are insufficient.".format(
                version=args.flutter_version
            )
        )

    return {
        "compatible": not blockers,
        "target": {
            "name": "Windows 7 SP1 x64",
            "version": list(TARGET_WINDOWS_VERSION),
        },
        "release_dir": str(release_dir),
        "manifest": str(args.manifest) if args.manifest else None,
        "installer_min_version": args.installer_min_version,
        "flutter_version": args.flutter_version,
        "blockers": sorted(set(blockers)),
        "warnings": sorted(set(warnings)),
        "pe_files": pe_reports,
    }


def write_text(path: Path | None, text: str) -> None:
    if not path:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-dir", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--installer-min-version")
    parser.add_argument("--flutter-version")
    parser.add_argument("--json", type=Path, dest="json_path")
    parser.add_argument("--markdown", type=Path)
    parser.add_argument(
        "--fail-on-incompatible",
        action="store_true",
        help="Return a non-zero exit code when any Windows 7 blocker is found.",
    )
    args = parser.parse_args(argv)

    report = analyze(args)
    json_text = json.dumps(report, indent=2, sort_keys=True)
    markdown_text = markdown_report(report)

    write_text(args.json_path, json_text + "\n")
    write_text(args.markdown, markdown_text)
    print(markdown_text)

    if args.fail_on_incompatible and not report["compatible"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
