# Homebrew Packaging

Tuck is distributed as a cask because one installation should provide both the native macOS app and the CLI.

The release archive must contain:

```text
Tuck.app
bin/tuck
```

Build the release archive and generate a checksum-pinned cask:

```sh
Scripts/package-release.sh 0.1.0
```

For a public release, create and install a Developer ID Application certificate, then store notarization credentials:

```sh
xcrun notarytool store-credentials tuck-notary --apple-id you@example.com --team-id TEAMID
```

`notarytool` prompts for an app-specific password when `--password` is omitted, which keeps it out of shell history.

Check the local setup:

```sh
Scripts/check-notarization-setup.sh
CHECK_NOTARY_PROFILE=1 Scripts/check-notarization-setup.sh
```

Then build the signed, notarized release archive:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARIZE=1 \
  NOTARY_PROFILE=tuck-notary \
  Scripts/package-release.sh 0.1.0
```

Upload `dist/Tuck-0.1.0.zip` to the GitHub release named `v0.1.0`, then copy `dist/homebrew/tuck.rb` into the tap at:

```text
homebrew-tuck/Casks/tuck.rb
```

Users can then install both surfaces with:

```sh
brew tap nathangathright/tuck
brew install --cask tuck
```

The cask declares `depends_on formula: "ffmpeg"` so the Homebrew install supplies the media tools. The app also checks bundled binaries first, which leaves room for a later fully self-contained distribution.
