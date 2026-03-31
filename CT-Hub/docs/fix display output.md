# Fix Display Output

## Problem

The shared PDF web reader is not using a true page-based zoom baseline.

Current behavior:
- Hub PDF Editor web mode needs Page Zoom X/Y around `67 / 67` to look correct.
- iOS reader needs Page Zoom X/Y around `200 / 300` to look correct.
- `100 / 100` does not represent a neutral default on either platform.

Root causes identified:
1. The shared reader in `CT-Hub/wwwroot/reader.html` fits content against `layout.bounds.width` and `layout.bounds.height`, which are cropped text-content bounds, not the full PDF page.
2. The shared reader also uses a device-local reference width (`readerViewportBaseWidth`), so Hub and iOS can interpret the same slider values against different local baselines.
3. Because of those two factors, the Page Zoom X/Y sliders are acting like compensation values instead of true zoom multipliers.

User-visible result:
- The same document requires different Page Zoom X/Y values on Hub and iOS to achieve the same visual size.
- `100 / 100` is misleading because it does not mean normal page fit.
- Reopen, device changes, and layout differences can all shift the apparent output size.

## Plan

1. Change the shared reader scale baseline to use full page dimensions.
Use `layout.pageWidth` and `layout.pageHeight` instead of `layout.bounds.width` and `layout.bounds.height` when computing the base fit scale.

2. Stop positioning runs relative to cropped bounds.
Use the original page-space coordinates for run placement rather than subtracting `layout.bounds.left` and `layout.bounds.top`.

3. Make `100 / 100` the neutral default on all platforms.
After the baseline fix, Page Zoom X/Y should behave as pure user multipliers on top of a canonical full-page fit.

4. Keep Hub and iOS on the same shared math.
Because both use `reader.html`, the fix should live in the shared reader so both platforms converge automatically.

5. Verify whether the default fit should be width-fit or full-page contain-fit.
Preferred check:
- Width-fit: fills available width but may make tall pages feel larger.
- Contain-fit: uses the smaller of width-fit and height-fit so the whole page fits more predictably.

6. Re-test the current known ticket examples on both platforms.
Success target:
- Hub web mode and iOS should both look correct at `100 / 100` or very close to it.
- The same PDF should not need separate compensating Page Zoom X/Y values on each platform.

## Relevant Files

- `CT-Hub/wwwroot/reader.html`
- `CT-Hub/MainWindow.xaml.cs`
- `CTRebuild/Views/PdfBrowserView.swift`
- `CTRebuild/Views/WebReaderView.swift`
