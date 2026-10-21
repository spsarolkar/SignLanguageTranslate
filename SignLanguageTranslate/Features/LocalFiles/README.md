# Local files

Open **Pipeline → Local files** or **Settings → Local files**. The full-screen
browser closes back to the existing workspace. It does not start, pause or
cancel downloads, extraction or training.

- **All features** recursively indexes `Documents/Datasets/Features`, matching
  the pipeline's `*_features.json` filenames. Search matches names and relative
  paths across datasets. Empty and corrupt files remain visible for inspection.
- Folder shortcuts open datasets, feature folders, downloads, models and
  checkpoints. **Training state** previews `Documents/TrainingState.json`.
  The home folder also lists every visible
  file/folder in the app's Documents directory. A folder that has not been
  created yet shows an unavailable-folder message; browsing does not create it.
- Feature inspection shows saved frame count/model names, frame selection,
  timestamp, detected-point counts, a normalized keypoint plot, and joint
  x/y/optional-z/confidence tables. These are saved values, not new inference
  or a quality guarantee. Empty files explicitly show zero saved frames.
- Video previews use the system player. The feature plot is an independent
  coordinate view; keypoint video overlays remain in the Pipeline clip player.
- JSON/text has selectable raw content. Images use thumbnails up to 1024 px.
  Archives and binary weights show file information without expansion.

## Snapshots and limits

Use the refresh button or pull down on a folder list to see newly generated
files. Search filters the current snapshot; it does not rescan the disk on
every keystroke. There is no automatic recursive watcher during extraction.

Text reads stop at 64 KiB plus one byte to detect truncation. Interactive
feature decoding and compressed image reads stop at 8 MiB plus one byte.
Larger feature files fall back to a clearly labelled text excerpt. Files are
opened for reading only. Atomic pipeline writes can appear after a refresh;
files that move/disappear produce a recoverable preview error.

`LocalFileStore` performs filesystem work in an actor and returns immutable
metadata/preview snapshots. No SwiftData context is passed to it. Paths are
relative to a supplied Documents root. Both the root and returned file URLs are
canonicalized before comparing path components, so filesystem aliases such as
`/var` and `/private/var` do not incorrectly reject files inside Documents.
Directory listings omit symlinks; navigation/preview rejects escapes outside
the root. The browser does not expose the app's Library/Keychain or other apps.

No delete, move, rename, upload, archive expansion or re-extraction action is
available here. Tests use isolated temporary folders, plus one uniquely named
fixture in the real app Documents directory that is removed after the test.
They verify canonical paths, escape rejection and preservation of original
bytes and modification timestamps.
