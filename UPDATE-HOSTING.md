# TapForge update hosting

TapForge releases are hosted on GitHub. Pushing a `vMAJOR.MINOR.PATCH` tag runs
the Windows release workflow, builds the app, and attaches a portable ZIP to a
GitHub Release. The workflow uses the repository's built-in token with only
`contents: write` permission.

## One-time setup

The public repository is at
https://github.com/saberapexyt-commits/TapForge. Its `origin` remote is set in
this folder. Git Credential Manager will request GitHub authorization the first
time Git pushes from this PC; complete that sign-in yourself if prompted.

Before the initial upload, configure a commit identity and commit the source:

```powershell
git config user.name "saberapexyt-commits"
git config user.email "saberapexyt-commits@users.noreply.github.com"
git add .
git commit -m "Set up TapForge release hosting"
git push -u origin main
git push origin v3.9.6
```

Pushing the initial release tag publishes the first portable ZIP.

## Publish a release

After committing your changes to the local source, run
`.\Publish-TapForgeUpdate.ps1 -Version 3.9.7` with the next version number.
The script pushes the source to `main`, creates a matching `v3.9.7` tag, and
pushes that tag. GitHub Actions then builds and publishes
`TapForge-v3.9.7-Portable.zip`.

TapForge checks the public releases feed when it opens and offers to download
and install a newer release. The development copy also has a **Publish update**
button on its Maintenance page; the portable package hides that publisher
button. A friend using an older package must install this update-enabled build
once before future releases can be installed from inside the app.
