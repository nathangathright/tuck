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
