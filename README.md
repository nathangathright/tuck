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
