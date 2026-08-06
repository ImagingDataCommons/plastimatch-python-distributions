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

**The build layer** (`superbuild/`, `.github/workflows/build-binaries.yml`) compiles zlib-ng,
ITK, DCMTK and dlib as static libraries, builds plastimatch against them, and attaches one
self-contained archive per platform to a GitHub release. This exists because upstream
plastimatch publishes source archives only — there is no official binary to download.

`superbuild/` is an `ExternalProject` chain in the style of dcmqi's `CMakeExternals/`, so one
CMake invocation builds everything in dependency order on all three platforms:

```console
cmake -S superbuild -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

Which plastimatch gets packaged is configurable, and defaults to the upstream GitLab
repository — this project does not fork plastimatch:

```console
cmake -S superbuild -B build \
  -DPLASTIMATCH_GIT_REPOSITORY=https://gitlab.com/plastimatch/plastimatch.git \
  -DPLASTIMATCH_GIT_TAG=1.10.0
```

Everything the build consumes is pinned by content, not by name. The four dependencies carry
a `URL_HASH SHA256`, and plastimatch is pinned to a full commit SHA with its tag recorded
alongside. A version number alone is not a pin: GitHub's auto-generated tag tarballs are not
guaranteed byte-stable, and a git tag is a mutable pointer — either could change what gets
compiled into a published binary with no signal. This matches how `plastimatchUrls.cmake`
pins the archives the wheels are built from, so the chain from upstream source to installed
wheel is checksummed end to end.

Linux builds run inside `manylinux_2_28` rather than on the runner. That is not incidental:
compiling on `ubuntu-24.04` produces binaries requiring glibc 2.38 and GLIBCXX_3.4.32, which
is newer than any manylinux image provides, so wheels built from them cannot be installed
anywhere — including in cibuildwheel's own test container. `scripts/check_binary_floor.sh`
asserts both floors after every Linux build.

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
