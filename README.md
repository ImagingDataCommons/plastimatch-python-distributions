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

## Current state

Nothing is published to PyPI yet, and the two layers described below are not yet joined up:
the build layer works but has not cut a release, so `plastimatchUrls.cmake` still pins
archives built by an older set of per-platform workflows in a **plastimatch fork**
(`fedorov/plastimatch`) that predates this repository.

That is the only reason the pins name a repository other than this one. Once the build layer
publishes a release, the pins move to this repository's own archives and the fork stops being
involved — see [Repointing the pins](#repointing-the-pins). Until then the two tables below
differ, and the first one is what `pip install` would actually get.

## Supported platforms

What the **currently pinned** archives support:

| Platform | Wheel tag | Minimum OS | Status |
| --- | --- | --- | --- |
| Windows x86_64 | `win_amd64` | Windows 10+ | working |
| macOS x86_64 (Intel) | `macosx_15_0_x86_64` | macOS 15 | working, floor too high |
| macOS arm64 (Apple Silicon) | `macosx_15_0_arm64` | macOS 15 | working, floor too high |
| Linux x86_64 | `manylinux_2_38_x86_64` | glibc 2.38 (Ubuntu 23.10+) | **not publishable** |

What the **build layer in this repository** produces:

| Platform | Wheel tag | Minimum OS |
| --- | --- | --- |
| Windows x86_64 | `win_amd64` | Windows 10+ |
| macOS x86_64 (Intel) | `macosx_13_0_x86_64` | macOS 13 |
| macOS arm64 (Apple Silicon) | `macosx_13_0_arm64` | macOS 13 |
| Linux x86_64 | `manylinux_2_28_x86_64` | glibc 2.28 (RHEL 8, Debian 10, Ubuntu 18.10+) |

The platform tags are derived from the bundled binaries rather than declared by hand (see
`scripts/retag_*_wheel.sh`), so they always describe what the wheel can actually run on, and
the wheel layer picks up the lower floors automatically once the pins move.

The floors in the first table are inherited from the runner images those binaries happened to
be compiled on, not from anything plastimatch requires. The Linux one is a hard blocker rather
than an inconvenience: glibc 2.38 is newer than any manylinux image pypa publishes, so that
wheel cannot be built or tested in a conforming environment at all — which is why the build
layer compiles inside `manylinux_2_28`, and why the Linux wheel job fails until the pins move.

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
nothing else, which means the wheel layer is indifferent to who produced the binaries. That
indifference is not hypothetical — it is what lets the pins currently reference a fork's
archives while the build layer is still being brought up, and it is why pointing this file at
upstream's own binaries and deleting the build layer would be the entire migration if
plastimatch ever publishes them.

## Repointing the pins

`plastimatchUrls.cmake` pins the exact archives a wheel is built from — a filename and a
SHA256 per platform. Regenerate that section from a release with:

```console
python scripts/update_plastimatch_urls.py --repo <owner>/<repo> --tag <tag>
```

The `--repo` to use is whichever one hosts the archives:

- `fedorov/plastimatch-python-distributions` — this repository, once `build-binaries.yml` has
  been dispatched with a `release_tag`. **This is the intended steady state.**
- `fedorov/plastimatch` — the fork whose older workflows produced the archives pinned today.
  Interim only.

Cutting a release is deliberately not automatic on push. The pins are checksums of specific
assets, so replacing the assets under an existing tag would break every wheel build pointing
at it; the workflow only attaches archives when a `release_tag` input is supplied explicitly.
For the same reason the pins should reference an immutable tag rather than a rolling one
before anything is published to PyPI.

## Versioning

A release version **is the upstream plastimatch version, exactly**, with packaging revisions
expressed as PEP 440 post-releases:

| Wheel version | Means |
| --- | --- |
| `1.10.0` | plastimatch 1.10.0 |
| `1.10.0.post1` | plastimatch 1.10.0 again — same upstream source, packaging fixed |
| `1.10.0.post2` | ditto, second packaging fix |
| `1.11.0` | plastimatch 1.11.0 |

So `pip install plastimatch==1.10.0` gets you plastimatch 1.10.0, which is the only thing a
user of this package is likely to reason about. These sort correctly:
`1.10.0 < 1.10.0.post1 < 1.11.0`.

Post-releases rather than the two obvious alternatives:

- **Not a fourth component** (`1.10.0.1`). PEP 440 defines `.postN` as precisely this case — a
  correction to a release with no change to the software itself — whereas `1.10.0.1` would read
  as an upstream plastimatch version that does not exist, sending anyone who saw it looking for
  a release that was never made. Upstream's own version numbers are three-component; it does
  generate a fourth from `git describe` (`PLM_VERSION_TWEAK`), but only for builds *between*
  tags, never for a release, so that slot already reads as "commits since tag" to anyone who
  has built plastimatch from git.
- **Not a local version** (`1.10.0+plm1`). PyPI rejects local version identifiers outright, so
  this is unavailable rather than merely worse.

The cost is that a packaging change is invisible unless you read the `.postN`, and that a
packaging fix cannot be pre-released. Both are acceptable for a wrapper whose version is a
claim about what is inside it.

Note that the two projects this one is modelled on disagree here:
`dcmqi-python-distributions` published `0.1.0` … `0.4.1` under its own numbering before
switching to upstream's (`1.5.6`), while `s5cmd-python-distributions` still numbers
independently. Mirroring upstream from the start avoids the one-way version jump that switch
required — published versions can only go up.

### Tags

There are two independent tag namespaces, because this repository publishes two different
kinds of thing:

| Tag | What it is | Published to |
| --- | --- | --- |
| `v1.10.0` | a release of *this package* | PyPI |
| `binaries-1.10.0-1` | a set of prebuilt plastimatch archives | GitHub release only |

Binaries releases exist so `plastimatchUrls.cmake` has immutable URLs to pin, and they are
re-cut whenever the build layer changes without any new upstream version. Keeping them out of
the version namespace matters in two places, both of which are configured rather than
conventional:

- `setuptools_scm` is restricted to `v`-prefixed tags. At its defaults it matches any tag
  containing a digit, and its `tag_regex` has an optional `[\w-]+-` prefix group, so it reads
  `binaries-1.10.0-1` as version `1.10.0` and the next commit builds as `1.10.0.post1.post1`.
- The PyPI upload job in `cd.yml` is gated on the release tag starting with `v`. It triggers on
  `release: published`, which a binaries release also is, so without the check every binaries
  release would publish a wheel built from whatever the pins referenced at the time.

Versions come from those tags via `setuptools_scm`, so cutting a release is tagging one.
`version_scheme = "post-release"` is set deliberately: the default, `guess-next-dev`, reports
an untagged commit after `v1.10.0` as `1.10.1.dev2`, inventing a *next upstream release* this
project neither controls nor may ever package. `post-release` reports `1.10.0.post2` instead.
Untagged builds also carry a local version segment (`+g<sha>`), which PyPI refuses, so a
development build cannot be uploaded by accident.

### Publishing

PyPI publishing uses Trusted Publishing (OIDC), so there is no API token to manage. Before the
first upload, a pending publisher has to be registered at
<https://pypi.org/manage/account/publishing/> with:

| Field | Value |
| --- | --- |
| PyPI project name | `plastimatch` |
| Owner | `fedorov` |
| Repository name | `plastimatch-python-distributions` |
| Workflow name | `cd.yml` |
| Environment name | `pypi` |

Registering the same on <https://test.pypi.org/manage/account/publishing/> allows a rehearsal
first, which is worth doing because a published version can never be reused.

Two things worth knowing before the first upload:

- **A published version can never be reused**, even after deleting the release. Rehearse on
  TestPyPI, not on the real index.
- Only tagged *upstream releases* get published here. Packaging an untagged upstream snapshot
  has no good PEP 440 spelling — `.postN` is already spoken for, and a `.devN` would sort
  before the release it comes after — so snapshots stay as GitHub release assets.

Because two `.postN` wheels can wrap different builds of the same upstream tag, the exact
upstream commit is recorded in each archive's filename and pinned in `plastimatchUrls.cmake`,
which is what makes a given wheel traceable to a source revision.

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
