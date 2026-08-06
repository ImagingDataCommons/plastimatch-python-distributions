# plastimatch Python distributions

Platform-specific Python wheels containing the official
[plastimatch](https://gitlab.com/plastimatch/plastimatch) command line executables, so that
plastimatch can be installed with

```console
pip install plastimatch
```

and used straight away:

```console
plastimatch synth --output sphere.mha --pattern sphere
plastimatch convert --input sphere.mha --output-dicom dicom/
```

Every tool is also callable from Python:

```python
from plastimatch import plastimatch
```

Installing the wheel places a launcher for each executable on `PATH` via
`[project.scripts]`. No compiler, no CMake, and no ITK or DCMTK installation is required —
the executables are statically linked.

This repository packages plastimatch; it does not modify it. It follows the recipe
established by
[s5cmd-python-distributions](https://github.com/ImagingDataCommons/s5cmd-python-distributions)
and
[dcmqi-python-distributions](https://github.com/ImagingDataCommons/dcmqi-python-distributions).

## Included tools

| Tool | Description |
| --- | --- |
| `plastimatch` | The main multi-command driver (`convert`, `register`, `warp`, `synth`, `dice`, …) |
| `dicom_uid` | Generate DICOM UIDs |

## Supported platforms

| Platform | Wheel tag | Minimum OS | Status |
| --- | --- | --- | --- |
| Windows x86_64 | `win_amd64` | Windows 10+ | working |
| macOS x86_64 (Intel) | `macosx_15_0_x86_64` | macOS 15 | working, floor too high |
| macOS arm64 (Apple Silicon) | `macosx_15_0_arm64` | macOS 15 | working, floor too high |
| Linux x86_64 | `manylinux_2_38_x86_64` | glibc 2.38 (Ubuntu 23.10+) | **not publishable yet** |

The platform tags are derived from the bundled binaries rather than declared by hand (see
`scripts/retag_*_wheel.sh`), so they always describe what the wheel can actually run on.

These floors are inherited from the runner images the binaries are compiled on, not from
anything plastimatch requires, and all three are lowered in the build layer rather than here.
The wheel layer picks up the lower floors automatically once the binaries change.

The Linux floor is a hard blocker rather than an inconvenience: glibc 2.38 is newer than any
manylinux image pypa publishes, so the wheel cannot be built or tested in a conforming
environment at all. Building plastimatch and its dependencies inside `manylinux_2_28` is a
prerequisite for publishing Linux wheels.

On macOS, `-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0` would restore support for macOS 13 and 14,
which currently covers a large share of Apple Silicon machines.

## How it works

The repository is deliberately split into two layers that meet at a single pinned URL.

```
 build-binaries.yml ──> per-platform archives ──> GitHub release
                                                       │
                                             plastimatchUrls.cmake   <-- the seam
                                                       │
                                              CMakeLists.txt + pyproject.toml
                                                       │
                                                     wheels ──> PyPI
```

**The build layer** (`deps/`, `.github/workflows/build-binaries.yml`) compiles ITK, DCMTK,
dlib and zlib-ng as static libraries, builds plastimatch against them, and attaches one
self-contained archive per platform to a GitHub release. This exists because upstream
plastimatch publishes source archives only — there is no official binary to download.

**The wheel layer** (`CMakeLists.txt`, `pyproject.toml`, `src/plastimatch/`) downloads one
of those archives, verifies its SHA256, and installs the executables into a Python package.
It does no compiling, so a wheel can be re-cut in seconds when only packaging metadata
changes.

`plastimatchUrls.cmake` is the seam. It names the archive and checksum for each platform and
nothing else, which means the wheel layer is indifferent to who produced the binaries. If
upstream plastimatch ever publishes its own release binaries, pointing this file at them and
deleting the build layer is the entire migration.

## Choosing which plastimatch version to package

`plastimatchUrls.cmake` pins the exact archives a wheel is built from. Regenerate it from a
release with:

```console
python scripts/update_plastimatch_urls.py --repo fedorov/plastimatch --tag <tag>
```

The wheel version itself comes from this repository's git tags via `setuptools_scm`. Tag
releases to match the upstream plastimatch version being packaged (`1.10.0`), and use a
`.postN` suffix (`1.10.0.post1`) for packaging-only fixes that ship the same binaries.

## Development

```console
pip install -e .          # builds the wheel layer against the pinned archives
pytest tests
```

The test suite checks that each launcher is installed and runnable, and puts the packaged
`plastimatch` through a DICOM write/read round-trip. That last test is the important one: a
plastimatch linked against a DCMTK whose data dictionary is loaded from a file at run time
passes its own unit tests in the build tree and then silently fails every DICOM read once
installed elsewhere.

## License

The packaging infrastructure in this repository is MIT licensed. plastimatch itself is
distributed under a BSD-style license, and the wheels bundle it statically linked against
ITK, DCMTK, dlib and zlib-ng. See [LICENSE](LICENSE) for details; the upstream license texts
are installed into `plastimatch/share/licenses/` inside each wheel.
