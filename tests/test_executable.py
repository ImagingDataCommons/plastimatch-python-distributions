from __future__ import annotations

import re
import subprocess
import sysconfig
from importlib.metadata import distribution
from pathlib import Path

import pytest

import plastimatch

from . import push_argv

_BINARIES_FILE = Path(__file__).parent.parent / "binaries.txt"
_EXPECTED_TOOLS = sorted(
    line.strip() for line in _BINARIES_FILE.read_text().splitlines() if line.strip()
)

all_tools = pytest.mark.parametrize("tool", _EXPECTED_TOOLS)


def _get_scripts():
    dist = distribution("plastimatch")
    scripts_paths = [
        Path(sysconfig.get_path("scripts", scheme)).resolve()
        for scheme in sysconfig.get_scheme_names()
    ]
    scripts = []
    for file in dist.files:
        if file.locate().parent.resolve(strict=True) in scripts_paths:
            scripts.append(file.locate().resolve(strict=True))
    return scripts


def _script_for(tool):
    scripts = [script for script in _get_scripts() if script.stem == tool]
    assert len(scripts) == 1, (
        f"expected exactly one {tool} console script, got {scripts}"
    )
    return scripts[0]


@all_tools
def test_console_script_installed(tool):
    """Every tool in binaries.txt gets a launcher on PATH."""
    assert _script_for(tool).exists()


def test_plastimatch_version():
    """
    `plastimatch --version` reports the upstream source revision it was built from, e.g.

        plastimatch version 8e65f51f

    The revision is not asserted here -- it changes with every upstream commit -- only that
    the executable runs and identifies itself.
    """
    output = subprocess.check_output(
        [str(_script_for("plastimatch")), "--version"], text=True
    )
    assert re.match(r"^plastimatch version \S+", output.strip())


def test_dicom_uid_generates_uid():
    """
    dicom_uid has no --version flag: it prints a freshly generated DICOM UID and treats any
    argument as a UID prefix. Assert it emits something UID-shaped.
    """
    output = subprocess.check_output([str(_script_for("dicom_uid"))], text=True).strip()
    assert re.fullmatch(r"[0-9]+(\.[0-9]+)+", output), output


@all_tools
def test_module_wrapper(tool):
    """Each tool is also exposed as a callable that exits with the executable's status."""
    func = getattr(plastimatch, tool)
    with push_argv([f"{tool}.py"]), pytest.raises(SystemExit) as excinfo:
        func()
    assert excinfo.value.code == 0


def test_dicom_round_trip(tmp_path):
    """
    Exercise the packaged binary end to end: synthesise an image, write it out as DICOM,
    read it back, and confirm the geometry survived.

    This is the test that matters most for a wheel. A plastimatch built against a DCMTK
    whose data dictionary is loaded from an external file at run time passes its own unit
    tests in the build tree and then fails every DICOM read once packaged and installed
    somewhere else -- with no error, just empty output. Only a round-trip through the
    installed executable catches that.
    """
    plm = str(_script_for("plastimatch"))
    synth = tmp_path / "sphere.mha"

    subprocess.run(
        [
            plm,
            "synth",
            "--output",
            str(synth),
            "--pattern",
            "sphere",
            "--dim",
            "24",
            "--origin",
            "-24 -24 -24",
            "--spacing",
            "2 2 2",
            "--center",
            "0 0 0",
            "--radius",
            "12",
        ],
        check=True,
        capture_output=True,
    )
    assert synth.stat().st_size > 0, "could not write an image"

    dicom_dir = tmp_path / "dcm"
    subprocess.run(
        [
            plm,
            "convert",
            "--input",
            str(synth),
            "--output-dicom",
            str(dicom_dir),
            "--output-type",
            "short",
        ],
        check=True,
        capture_output=True,
    )
    assert list(dicom_dir.glob("*.dcm")), "wrote no DICOM"

    restored = tmp_path / "round_trip.mha"
    subprocess.run(
        [plm, "convert", "--input", str(dicom_dir), "--output-img", str(restored)],
        check=True,
        capture_output=True,
    )
    assert restored.stat().st_size > 0, (
        "could not read back DICOM -- is the DCMTK data dictionary compiled in?"
    )

    header = subprocess.check_output([plm, "header", str(restored)], text=True)
    assert "Size = 24 24 24" in header, header
    assert "Spacing = 2.0000 2.0000 2.0000" in header, header
