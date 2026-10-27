#!/usr/bin/env python3
"""Render a strictly non-physical AD5M macro with official Klipper code.

The harness imports only Klipper's gcode_macro module from a caller-provided,
clean official checkout at the revision locked in the fixture.  It renders a
template but never gives Klipper an executor, transport, Moonraker endpoint,
or hardware object.
"""

from __future__ import annotations

import configparser
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from types import ModuleType

# The checked-out official source is test input, never a directory for test
# artifacts.  Importing its module must not create __pycache__ there.
sys.dont_write_bytecode = True


class HarnessError(RuntimeError):
    """A fixture or source-integrity invariant was not met."""


class UnsafeCommandError(HarnessError):
    """Rendered text contained a command outside the fixture allow-list."""


class FakeGCode:
    """Only the documented error callback needed while constructing a template."""

    @staticmethod
    def error(message: str) -> HarnessError:
        return HarnessError(message)


class FakePrinter:
    """No-op object registry used only by Klipper's TemplateWrapper setup."""

    def __init__(self) -> None:
        self.objects: dict[str, object] = {"gcode": FakeGCode()}

    def lookup_object(self, name: str, default: object | None = None) -> object | None:
        return self.objects.get(name, default)

    @staticmethod
    def config_error(message: str) -> HarnessError:
        return HarnessError(message)


class FakeConfig:
    """Minimal config adapter for PrinterGCodeMacro.load_template()."""

    def __init__(self, printer: FakePrinter, section: str, gcode: str) -> None:
        self.printer = printer
        self.section = section
        self.gcode = gcode

    def get_printer(self) -> FakePrinter:
        return self.printer

    def get_name(self) -> str:
        return self.section

    def get(self, option: str, default: str | None = None) -> str | None:
        if option == "gcode":
            return self.gcode
        return default


def fail(message: str) -> None:
    raise HarnessError(message)


def run_git(source: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(source), *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        fail(f"cannot inspect Klipper source with git {' '.join(args)}: {detail}")
    return result.stdout.strip()


def load_case(repo_root: Path) -> dict[str, object]:
    case_path = repo_root / "tests/fixtures/macro-golden/load-material-action.json"
    try:
        return json.loads(case_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read macro golden fixture {case_path}: {error}")


def verify_source(source: Path, source_lock: dict[str, object]) -> Path:
    module_path = source / "klippy/extras/gcode_macro.py"
    if not module_path.is_file():
        fail(f"missing official Klipper macro module: {module_path}")
    expected_revision = source_lock.get("commit")
    if not isinstance(expected_revision, str) or len(expected_revision) != 40:
        fail("fixture has no valid 40-character official Klipper commit")
    if run_git(source, "rev-parse", "HEAD") != expected_revision:
        fail(f"Klipper revision mismatch: expected {expected_revision}")
    if run_git(source, "status", "--porcelain", "--untracked-files=normal"):
        fail(f"Klipper checkout is not clean: {source}")
    remote_url = run_git(source, "remote", "get-url", "origin")
    expected_remote = source_lock.get("remote")
    if remote_url != expected_remote:
        fail(f"Klipper origin mismatch: expected {expected_remote}, found {remote_url}")
    expected_module_sha256 = source_lock.get("gcode_macro_sha256")
    if not isinstance(expected_module_sha256, str) or len(expected_module_sha256) != 64:
        fail("fixture has no valid gcode_macro.py SHA-256")
    actual_module_sha256 = hashlib.sha256(module_path.read_bytes()).hexdigest()
    if actual_module_sha256 != expected_module_sha256:
        fail(
            "Klipper gcode_macro.py checksum mismatch: "
            f"expected {expected_module_sha256}, found {actual_module_sha256}"
        )
    return module_path


def load_official_module(module_path: Path) -> ModuleType:
    module_name = "ad5m_official_klipper_gcode_macro"
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        fail(f"cannot load official Klipper macro module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_macro_gcode(config_path: Path, section: str) -> str:
    parser = configparser.RawConfigParser(interpolation=None)
    parser.optionxform = str
    try:
        with config_path.open(encoding="utf-8") as config_file:
            parser.read_file(config_file)
        return parser.get(section, "gcode")
    except (OSError, configparser.Error) as error:
        fail(f"cannot read macro {section!r} from {config_path}: {error}")


def render_gcode(klipper_module: ModuleType, section: str, gcode: str) -> list[str]:
    printer = FakePrinter()
    config = FakeConfig(printer, section, gcode)
    macro_support = klipper_module.PrinterGCodeMacro(config)
    printer.objects["gcode_macro"] = macro_support
    rendered = macro_support.load_template(config, "gcode").render()
    return [line.strip() for line in rendered.splitlines() if line.strip()]


def assert_only_allowed_commands(lines: list[str], allowed_commands: list[str]) -> None:
    allowed = {command.upper() for command in allowed_commands}
    for line in lines:
        command = line.split(maxsplit=1)[0].upper()
        if command not in allowed:
            raise UnsafeCommandError(
                f"unexpected rendered command {command!r} in line: {line}"
            )


def read_expected_lines(path: Path) -> list[str]:
    try:
        return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    except OSError as error:
        fail(f"cannot read expected macro output {path}: {error}")


def main() -> int:
    if len(sys.argv) != 2:
        raise HarnessError(f"usage: {sys.argv[0]} <ad5m_enhanced_mod-root>")
    repo_root = Path(sys.argv[1]).resolve()
    if "build_output" in repo_root.parts:
        raise HarnessError(f"refusing a build-output path as repository root: {repo_root}")
    source_text = os.environ.get("KLIPPER_SOURCE_DIR", "")
    if not source_text:
        raise HarnessError(
            "KLIPPER_SOURCE_DIR is required; provide a clean official Klipper checkout"
        )
    source = Path(source_text).resolve()
    case = load_case(repo_root)
    source_lock = case.get("official_klipper")
    if not isinstance(source_lock, dict):
        raise HarnessError("fixture has no official_klipper source lock")
    module_path = verify_source(source, source_lock)
    module = load_official_module(module_path)

    macro_file = case.get("macro_file")
    section = case.get("macro_section")
    allowed_commands = case.get("allowed_commands")
    expected_output = case.get("expected_output")
    if not all(isinstance(value, str) for value in (macro_file, section, expected_output)):
        raise HarnessError("fixture has an invalid macro path, section, or expected-output path")
    if not isinstance(allowed_commands, list) or not all(
        isinstance(command, str) for command in allowed_commands
    ):
        raise HarnessError("fixture has an invalid command allow-list")

    lines = render_gcode(module, section, read_macro_gcode(repo_root / macro_file, section))
    assert_only_allowed_commands(lines, allowed_commands)
    expected_lines = read_expected_lines(repo_root / expected_output)
    if lines != expected_lines:
        raise HarnessError(
            "golden output mismatch:\n"
            f"expected: {expected_lines}\n"
            f"actual:   {lines}"
        )

    negative_path = repo_root / "tests/fixtures/macro-golden/unexpected-command.gcode"
    try:
        assert_only_allowed_commands(read_expected_lines(negative_path), allowed_commands)
    except UnsafeCommandError:
        pass
    else:
        raise HarnessError("negative command fixture unexpectedly passed the safety allow-list")

    print(f"ok: official Klipper source matches {source_lock['commit']}")
    print(f"ok: {section} rendered {len(lines)} RESPOND commands matching its golden output")
    print("ok: unexpected physical-command fixture is rejected")
    print("macro golden validation passed (template/control-flow only)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HarnessError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
