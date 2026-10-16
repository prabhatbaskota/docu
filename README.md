# docu

This repository contains three applications:

| Directory | Application | Build or run instructions |
| --- | --- | --- |
| [`mobile/`](mobile/) | Flutter scanner and PDF toolkit for Android and iOS | [Mobile README](mobile/README.md) |
| [`desktop/`](desktop/) | Flutter Windows PDF library and editor | [Desktop README](desktop/README.md) |
| [`streamlit/`](streamlit/) | Original Streamlit PDF Worker | [Streamlit README](streamlit/README.md) |

The apps have separate dependencies and entry points. Run Flutter commands from
`mobile/` or `desktop/`, and Streamlit commands from `streamlit/`.

## Releases

The [Windows installer](https://github.com/prabhatbaskota/pdf-merger/releases/latest)
was released from the earlier desktop repository. The repository-root
[Windows workflow](.github/workflows/windows-release.yml) builds `desktop/`.

The newest local Android preview APK is in `release/`. It is signed with the
project's debug key and uses the placeholder package ID, so it is for direct
testing only. APKs and other build output are excluded from Git. See
[mobile/PLAY_RELEASE.md](mobile/PLAY_RELEASE.md) for the signed Android release
and Google Play handoff.

The previous Git repository metadata was backed up locally in
`.git-backup-pdf_merger-20261016/` before moving `.git` to this directory. The
backup is excluded from Git.

The one-time [local cleanup script](scripts/cleanup-local.ps1) checks the
duplicate pre-migration mobile source before removing it and older build
artifacts. Review its targets or run it with `-WhatIf` before applying it.
