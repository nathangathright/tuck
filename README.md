# Tuck

Dock-first macOS video compression.

Tuck is a lightweight native macOS app for making smaller, share-ready copies of videos without asking users to understand codecs, bitrates, or export settings. It is intended for designers and creators sharing screen recordings, product demos, presentations, and camera footage.

## Product Shape

- Native Swift and AppKit.
- macOS 14 or newer.
- Lives in the Dock without a main window.
- Clicking the Dock icon opens the native macOS file picker.
- Dropping videos on the Dock icon starts compression immediately.
- Multiple videos are processed sequentially.
- Completed files appear selected in Finder.
- Errors appear only when user action is required.

## Dock Status

- `...` while analyzing.
- Percentage while compressing.
- Checkmark when complete.
- `!` when something fails.

## Compression Behavior

Tuck should inspect codec, resolution, frame rate, duration, audio, subtitles, and file size. It should sample downscaled frames to distinguish mostly static content from sustained motion, then choose an appropriate profile:

- Screen recordings and slides: H.264, CRF 28, slow preset, 96 kbps AAC.
- Mixed or general video: H.264, CRF 24, slow preset, 128 kbps AAC.
- High-motion or dynamic 4K video: HEVC, CRF 26, medium preset, `hvc1`, 128 kbps AAC.

Outputs should preserve original resolution, frame rate, metadata, audio, and subtitles where practical, and produce a fast-start MP4 with broad Apple compatibility.

Save beside the source as:

```text
Original filename - compressed.mp4
```

If that file exists, append a number. Never overwrite, alter, or delete the original.

## Media Tools

Use FFmpeg and FFprobe, either bundled or discovered in common Homebrew locations. Show a clear installation error if the tools are unavailable.

## Flows To Verify

- Clicking the icon while closed opens the picker.
- Clicking it while idle opens the picker.
- Canceling the picker returns to an idle Dock state.
- Dropping a video while closed compresses it without showing the picker.
- Dropping additional videos queues them.
- Multi-selection works.
- Outputs decode successfully.
- Originals remain unchanged.

## Build and Run

Tuck is a Swift/AppKit macOS 14+ app with no main window. The Swift package keeps the compression pipeline testable, and `Scripts/build-app.sh` wraps the executable in a Launch Services `.app` bundle so Dock clicks and Dock file drops work like a normal Mac app.

```sh
swift test
Scripts/build-app.sh
open build/Tuck.app
```

The built app appears in `build/Tuck.app`.

The command-line tool uses the same compression engine:

```sh
swift run tuck /path/to/video.mov
```

It prints completed output paths to stdout, progress to stderr, and supports newline-delimited JSON events:

```sh
swift run tuck --json /path/to/video.mov
```

## FFmpeg

Tuck looks for `ffmpeg` and `ffprobe` in the app bundle first, then in common Homebrew locations and `PATH`.

For local development:

```sh
brew install ffmpeg
```

For bundled distribution, place executable binaries at:

```text
Vendor/ffmpeg/ffmpeg
Vendor/ffmpeg/ffprobe
```

`Scripts/build-app.sh` copies those into `Tuck.app/Contents/Resources/bin`.

## Verification Notes

Automated tests cover output naming, profile selection, FFmpeg-based compression, output decoding with FFprobe, and original-file preservation when FFmpeg is installed. Manual Dock flows still need to be exercised against the built app:

```sh
Scripts/smoke-test.sh
open build/Tuck.app
open -a "$(pwd)/build/Tuck.app" /path/to/video.mov
```

## Homebrew Distribution

The intended Homebrew shape is one cask that installs both the GUI and CLI:

```sh
brew tap nathangathright/tuck
brew install --cask tuck
```

`Scripts/package-release.sh` builds `dist/Tuck-0.1.0.zip` with this layout:

```text
Tuck.app
bin/tuck
```

It also generates `dist/homebrew/tuck.rb` from the template in `Packaging/Homebrew/Casks/tuck.rb.template`. Upload the zip to the matching GitHub Release, then copy the generated cask into the Homebrew tap.

For public distribution, install a Developer ID Application certificate and store a `notarytool` keychain profile, then run:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARIZE=1 \
  Scripts/package-release.sh 0.1.0
```
