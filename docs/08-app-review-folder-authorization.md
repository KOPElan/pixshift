# Output-folder authorization follow-up

Submission: 0149a0e6-db0f-4354-aee1-7f528e5346c4, reviewed October 13, 2026,
version 1.0 (2), Guideline 2.1(a).

Apple reported that exporting to an authorized folder separate from the source
folder displayed “Folder authorization required”.

## Changes

- Enable `com.apple.security.files.bookmarks.app-scope`, alongside the existing
  sandbox and user-selected read/write entitlements. The app uses security-scoped
  bookmarks for the saved output folder and interrupted-run recovery.
- Hold security-scoped access while creating output-folder bookmarks, refresh
  stale bookmarks, and discard invalid bookmarks or an old bookmark when saving
  a new selection fails.
- When the user reauthorizes the configured output folder, use and save the newly
  granted URL for preflight and export.
- Preserve the selected output folder when the folder picker is cancelled.

Apple documents the bookmark entitlement in
[Enabling Security-Scoped Bookmark and URL Access](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access).

## Verification on October 13, 2026

- macOS 27.0.1, Apple Silicon: 49 automated tests passed.
- New regression tests cover invalid-bookmark recovery and exporting an image
  from a separate source directory through a saved and resolved output bookmark.
  These automated tests run without signing and do not reproduce Powerbox grants.
- Apple Development signed Release build succeeded; `codesign --verify --strict`
  passed and the sandbox, user-selected read/write, and bookmark entitlements
  were verified in the signed product.
- Interactive signed Release test: select a PNG outside the sandbox, select a
  separate output folder outside the sandbox, and export. Result: one success,
  zero failures, with a 64 × 64 JPEG in the chosen output folder.
- Quit and relaunch the signed Release app, import the source again, and export
  using the restored output folder without selecting or authorizing it again.
  Result: one success, zero failures; collision avoidance preserved the first JPEG.

The original rejection was not reproduced reliably in the pre-change Debug app.
The missing entitlement and bookmark lifecycle gaps were found by inspection;
they are not a proven explanation of Apple's exact session. macOS 27.0 and the
App Store distribution archive still need a final release check.

## Before resubmission

1. Archive with the App Store signing configuration and a build number greater
   than 2, retaining the submitted marketing version as appropriate.
2. Verify the archived app contains all three file-access entitlements above.
3. Repeat separate-folder export on a clean installation and after relaunch;
   also verify source-folder export with both file and folder imports.
4. Upload the tested build and update the review notes with the steps above.

## Suggested App Store Connect reply after uploading the tested build

Thank you for reporting the output-folder authorization issue. We have updated
the sandbox bookmark configuration and folder authorization handling, including
restoring saved permissions and retaining newly granted folder access.

We verified export to a folder separate from the original image's folder in a
signed Release build on macOS 27.0.1, both immediately after selecting the output
folder and after quitting and reopening the app. Both exports completed
successfully without an additional folder authorization prompt.

To test the updated build, import an image, choose Unified Folder as the export
destination, select a different folder, and start processing. The generated
image is saved in that folder. The selected output folder is also retained for
the next launch.
