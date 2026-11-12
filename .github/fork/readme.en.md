## About this fork

[Xitaoyou/VeneraX](https://github.com/Xitaoyou/VeneraX) is a personal iOS fork of [Kyosee/VeneraX](https://github.com/Kyosee/VeneraX), which derives from [venera-app/venera](https://github.com/venera-app/venera). Credit and the original license are retained. This section describes fork-specific changes; the upstream introduction and documentation follow below.

### Fork additions and fixes

| Area | Behavior and compatibility |
| --- | --- |
| Pull down to dismiss the reader | Enabled on iOS for horizontal gallery and continuous reading, in both LTR and RTL directions. Vertical reading disables it silently. |
| Pull down to dismiss previews | Supported in fullscreen cover and favorite-image previews. |
| Dismissal animation | Reader images and toolbar shrink/fade as one page over a stationary background. Previews return to a visible matching thumbnail when available, otherwise collapse as a page. Canceled gestures rebound; reduced motion is respected. |
| Favorites and zoom gestures | Swipe collection disables downward dismissal and shows a conflict notice in settings. Zoomed images retain panning; pinch, page turns, long press and existing edge-back gestures are preserved. |
| Back swipes over comic cards | Closed cards in search and comic lists allow rightward back swipes over covers and text, including favorited comics. Left-swipe actions remain available; right swipes close an already open action pane before navigating away. |
| Upstream control compatibility | The animation route supplies the Material ancestor required by the upstream reader's new progress slider. |
| Fork update source | Manual and startup update checks use this repository, with its own Releases and AltStore / SideStore feed. Build numbers distinguish fork rebuilds of the same upstream version. |

These gesture changes are iOS-only. Automated regressions cover reading directions, real image widgets, zoom, collection conflicts, comic cards and route animations; device behavior still requires installation and testing.

### Downloads and installation

- **Fork iOS IPA:** [Latest release](https://github.com/Xitaoyou/VeneraX/releases/latest). Releases retain the upstream version and add an independently increasing build number, tagged `vVERSION+BUILD`.
- **AltStore / SideStore feed:** [altstore-source.json](https://github.com/Xitaoyou/VeneraX/releases/latest/download/altstore-source.json).
- IPAs are unsigned and require your own signing tool. In-app iOS updates open this fork's release page; they do not silently install an IPA. Signing tools can check the feed above.
- For upstream Android, Windows, macOS and Linux packages, use [Kyosee/VeneraX Releases](https://github.com/Kyosee/VeneraX/releases). This fork's dedicated publishing workflow targets iOS.

### Upstream sync and automatic releases

The [**Fork iOS workflow**](https://github.com/Xitaoyou/VeneraX/actions/workflows/fork-ios.yml) attempts to sync upstream `master` every six hours and supports manual runs. Merge conflicts stop the sync. Only successful static checks, gesture regressions and IPA compilation publish a release; failures leave the previous published package available.

Fork README sections are stored separately and combined with the upstream body. Independent translation edits merge by key; application code or competing translation edits stop with paths listed in the Actions summary. Scheduled runs retry unpublished application changes after a failed build.

README, changelog, installation manifest and other recognized metadata-only changes still sync but skip IPA compilation. Application code, bundled resources, dependencies and build configuration trigger builds; manual runs force a build. Fork-owned CI configuration is retained separately, so upstream workflow changes require review. Automatic merging cannot guarantee compatibility with all future upstream changes.

See the [fork design notes](.github/fork/DESIGN.md) for implementation details. The upstream introduction and general build instructions below are retained for reference; use this section for fork downloads, update sources and iOS publishing rules.

---

## Upstream project information
