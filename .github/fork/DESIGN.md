# Personal iOS fork

Repository: https://github.com/Xitaoyou/VeneraX
Upstream: https://github.com/Kyosee/VeneraX (master)

## Gesture policy

| Surface / state | Downward dismissal |
| --- | --- |
| Horizontal gallery, LTR or RTL | Enabled |
| Horizontal continuous reader, LTR or RTL | Enabled |
| Vertical gallery / continuous reader | Disabled silently |
| Cover / image favorites fullscreen preview | Enabled |
| Effective quickCollectImage = Swipe | Disabled; settings show the conflict |
| Image zoomed above its initial fit / fill scale | Disabled; drag pans image |
| Multiple pointers, canceled stream, mouse, upward / horizontal / short drag | Never dismiss |
| Reader chapter comments or loading | Disabled |
| A dialog / sheet covers the route | Disabled |

The opt-in `ImageSurfaceRoute` owns the entire page transition. The reader,
its image and toolbar move together with capped 80px translation and 6% scale;
release collapses/fades the whole card in 220ms instead of moving offscreen.
The route suppresses the previous page's secondary horizontal animation.
Opaque overlay entries become transparent only during a drag/exit, restoring
underlying content without keeping it painting throughout a reading session.

Cover/favorite previews freeze their release transform while a Hero returns to
the currently visible matching thumbnail. A decoded image clone keeps the flight
stable while source/destination placeholders are installed; crop and corner
radius interpolate continuously. Missing, clipped, offscreen or ambiguous targets
fall back to whole-page collapse. Only the current gallery image has a Hero.
Cancel/veto rebounds in 200ms. Reduced motion disables scale/translation and Hero
flight. Existing tap/edge-back behavior and non-iOS route choices are retained.

Only iOS enables this feature. It needs one downward touch gesture of at least
100 logical pixels, with vertical displacement more than twice horizontal
displacement. Direction locks after 18 pixels. A horizontal or upward gesture
cannot turn into a dismiss gesture midway. Policy and zoom are checked at
pointer down, every move, and release; there is no persisted shadow setting.

The reader integrates the recognition-only `PullDownToDismiss` inside its existing pointer listener,
around the actual `_ReaderImages` subtree. Raw pointer observation is deliberate:
a parent `GestureDetector.onVerticalDrag*` loses the gesture arena to PhotoView's
scale recognizer, even when the picture is not zoomed. Existing tap, double tap,
long press, horizontal paging, collection and edge-back handling remain with
their original recognizers. Preview controllers also use their actual initial
scale, rather than treating scale=1 as the fit size.

## Updating and upstream merges

Manual checks and startup checks share `checkUpdateUi` and the fork repository
constants. iOS opens the fork Release page; installing an unsigned IPA requires
the user's signing app. The release also contains an AltStore/SideStore feed:

https://github.com/Xitaoyou/VeneraX/releases/latest/download/altstore-source.json

Keep the existing app bundle ID. A signing team or bundle ID change may prevent
an in-place update; users should export a backup before changing installations.
The fork keeps the upstream marketing version, builds with a monotonic fork
build number, tags `vVERSION+BUILD`, and compares both in update checks.

`fork-ios.yml` runs on master pushes, manual dispatch, and every six hours.
Scheduled runs merge upstream application code normally and preserve the
fork-owned `.github` directory. Other merge conflicts stop the job. Upstream
workflow changes must be reviewed manually. The normal GitHub token can push
application merges without modifying workflow files; the same run builds the
merged SHA, so it does not depend on a token push triggering another workflow.

The source job pins `codex/ios-build` to the build SHA before compiling. This
keeps an existing branch reference even when master advances during a build,
so release creation does not require an extra workflow-scoped secret under
[GitHub's release permission rule](https://github.blog/changelog/2023-11-02-github-actions-enforcing-workflow-scope-when-creating-a-release/).
Every push runs the lightweight source job. `should_build.py` compares the
push's previous SHA, or a scheduled merge's before/after SHAs. Changes confined
to root README/CHANGELOG and project policy/license documents, root AltStore
manifests, or fork design/release notes skip the expensive IPA build. They still
merge normally. Bundled `doc/*.md`, assets, application code, dependencies,
workflow and publishing scripts all trigger builds; unknown paths or missing
baselines conservatively build. Manual dispatch always forces a build.
The build pins the standard `macos-15-intel` runner (Flutter x64, Xcode 16.4).
The generic `macos-15` ARM pool previously canceled a build after failing to
allocate a hosted runner; using the Intel label avoids that specific pool.

Only a successful analysis, regression suite and IPA build publish a new Release.
Failed sync or build keeps the previously released IPA available. Upstream
semantic changes can still require manual adaptation; automatic merging is not
a guarantee of future compatibility.

The feed extracts privacy permissions and the bundle identifier from the built
IPA rather than carrying an empty permission declaration. This follows the
[AltStore source format](https://faq.altstore.io/developers/make-a-source).

## Verification

`reader_pull_down_integration_test.dart` mounts the production Reader, including
its scaffold, image loader and gallery/continuous view, with real local PNGs.
It verifies all six reading directions and live collection-policy changes.
`pull_down_to_dismiss_test.dart` uses real PhotoView and PhotoViewGallery widgets
to cover horizontal paging followed by dismissal, zoom/pan, pinch, cancel,
short/upward drags, disabled policy and policy changes during a drag.
`ios_back_swipe_zoomed_image_test.dart` retains upstream edge-back regression
coverage; `fork_release_version_test.dart` covers same-version fork rebuilds.

`image_surface_route_test.dart` uses real AppPageRoute/ImageSurfaceRoute pairs
to check stationary backgrounds, whole-page chrome, visible/nested Hero targets,
offscreen fallback, disposal, reduced motion and PopScope veto.

Before using a new IPA as the main installation, validate on an iPhone: LTR/RTL
page turns then down-drag; vertical reading; swipe collection and its warning;
pinch zoom, double-tap and long-press zoom then pan; cover and favorites previews;
comments; dialogs; existing edge-back; switching reading mode during the session.
