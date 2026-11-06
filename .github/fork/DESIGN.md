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

Only iOS enables this feature. It needs one downward touch gesture of at least
100 logical pixels, with vertical displacement more than twice horizontal
displacement. Direction locks after 18 pixels. A horizontal or upward gesture
cannot turn into a dismiss gesture midway. Policy and zoom are checked at
pointer down, every move, and release; there is no persisted shadow setting.

The reader integrates `PullDownToDismiss` inside its existing pointer listener,
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

Before using a new IPA as the main installation, validate on an iPhone: LTR/RTL
page turns then down-drag; vertical reading; swipe collection and its warning;
pinch zoom, double-tap and long-press zoom then pan; cover and favorites previews;
comments; dialogs; existing edge-back; switching reading mode during the session.
