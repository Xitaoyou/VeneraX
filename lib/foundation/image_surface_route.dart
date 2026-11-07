import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:venera/foundation/app_page_route.dart';

/// Opt-in route for iOS readers and photo previews. A downward dismissal owns
/// the WHOLE page, including its chrome; there is no second horizontal pop.
class ImageSurfaceRoute<T> extends PageRoute<T> {
  ImageSurfaceRoute({
    required this.builder,
    this.preview = false,
    super.settings,
  });

  final WidgetBuilder builder;
  final bool preview;
  late final AnimationController _drag;
  bool _disposed = false;
  bool _interactive = false;
  bool _finishing = false;
  bool _pullPop = false;
  bool _heroReturn = false;
  bool _reduceMotion = false;
  Widget? _page;
  ui.Image? _flightImage;

  void _refresh() {
    if (overlayEntries.isNotEmpty) {
      overlayEntries.first.opaque =
          opaque && animation!.status == AnimationStatus.completed;
    }
    changedInternalState();
  }

  bool get isDismissing => _interactive || _finishing;

  @visibleForTesting
  bool get debugReturnsToThumbnail => _heroReturn;

  @override
  bool get opaque => !_interactive && !_pullPop;
  @override
  bool get maintainState => true;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);
  @override
  Duration get reverseTransitionDuration =>
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

  // The underlying page stays at its original coordinates even while our
  // opaque overlay becomes transparent. Its secondary slide must never run.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  void install() {
    super.install();
    _drag = AnimationController(
      vsync: navigator!,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _flightImage?.dispose();
    _drag.dispose();
    super.dispose();
  }

  bool beginPull(BuildContext context) {
    if (_disposed ||
        _finishing ||
        !isCurrent ||
        navigator!.userGestureInProgress ||
        animation!.status != AnimationStatus.completed ||
        popDisposition == RoutePopDisposition.doNotPop) {
      return false;
    }
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _drag.stop();
    _interactive = true;
    _refresh();
    return true;
  }

  void updatePull(double distance) {
    if (_disposed || !_interactive || _finishing) return;
    _drag.value = (distance / 240).clamp(0.0, 1.0);
  }

  Future<void> cancelPull() async {
    if (_disposed || !_interactive || _finishing) return;
    _finishing = true;
    try {
      await _drag
          .animateBack(
            0,
            duration: _reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    _finishing = false;
    _interactive = false;
    _refresh();
  }

  Future<void> finishPull(bool Function() enabled, Object? heroTag) async {
    if (_disposed || !_interactive || _finishing) return;
    _finishing = true;
    // Rebuild the previously opaque route beneath us before finding its Hero.
    await SchedulerBinding.instance.endOfFrame;
    if (_disposed || !isCurrent || !isActive) return;
    if (!enabled()) {
      _finishing = false;
      await cancelPull();
      return;
    }
    _heroReturn = preview && !_reduceMotion && _hasVisibleSource(heroTag);
    _flightImage?.dispose();
    _flightImage = _heroReturn ? _captureHeroImage(heroTag) : null;
    _heroReturn = _heroReturn && _flightImage != null;
    _pullPop = true;
    _refresh();
    // Freeze the drag transform so Hero measures the actual release rectangle.
    // Disable unrelated/offscreen Heroes before the Navigator captures them.
    await SchedulerBinding.instance.endOfFrame;
    if (_disposed || !isCurrent || !isActive) return;
    try {
      if (enabled()) await navigator!.maybePop();
    } finally {
      if (!_disposed && isCurrent && isActive) {
        _pullPop = false;
        _finishing = false;
        _heroReturn = false;
        _refresh();
        await cancelPull();
      }
    }
  }

  ui.Image? _captureHeroImage(Object? tag) {
    ui.Image? image;
    void scanImage(Element e) {
      final w = e.widget;
      if (w is RawImage && w.image != null && image == null) {
        image = w.image!.clone();
      }
      if (image == null) e.visitChildren(scanImage);
    }

    void scan(Element e) {
      if (e.widget is Hero &&
          (e.widget as Hero).tag == tag &&
          ModalRoute.of(e) == this) {
        scanImage(e);
      } else if (image == null) {
        e.visitChildren(scan);
      }
    }

    (navigator!.context as Element).visitChildren(scan);
    return image;
  }

  bool _hasVisibleSource(Object? tag) {
    if (tag == null) return false;
    var matches = 0;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is Hero &&
          widget.tag == tag &&
          ModalRoute.of(element) != this) {
        final box = element.findRenderObject();
        if (box is RenderBox &&
            box.attached &&
            box.hasSize &&
            !box.size.isEmpty) {
          final bounds = MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          );
          var visible = Offset.zero & MediaQuery.sizeOf(element);
          RenderObject child = box;
          var parent = child.parent;
          while (parent != null) {
            final clip = parent.describeApproximatePaintClip(child);
            if (clip != null) {
              visible = visible.intersect(
                MatrixUtils.transformRect(parent.getTransformTo(null), clip),
              );
            }
            child = parent;
            parent = child.parent;
          }
          final intersection = visible.intersect(bounds);
          if (!intersection.isEmpty &&
              intersection.width * intersection.height >=
                  bounds.width * bounds.height * 0.95) {
            matches++;
          }
        }
      }
      element.visitChildren(visit);
    }

    (navigator!.context as Element).visitChildren(visit);
    return matches == 1;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    // Match AppPageRoute's Material ancestor. Upstream reader controls (such
    // as Slider) rely on it even when the page has no Material Scaffold.
    child: _page ??= Material(child: Builder(builder: builder)),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final body = AnimatedBuilder(
      animation: Listenable.merge([animation, _drag]),
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        if (_interactive || _pullPop) {
          final p = _reduceMotion ? 0.0 : _drag.value;
          final t = _pullPop
              ? Curves.easeOutCubic.transform(1 - animation.value)
              : 0.0;
          // The entire reader settles near its release position; it never
          // travels below the screen. Hero flies separately in the overlay.
          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Theme.of(context).colorScheme.surface.withValues(
                  alpha: (1 - 0.45 * p) * (1 - t),
                ),
              ),
              Transform.translate(
                key: const ValueKey('image-surface-translation'),
                offset: Offset(0, 80 * p * (_heroReturn ? 1 : 1 - 0.35 * t)),
                transformHitTests: false,
                child: Transform.scale(
                  scale:
                      1 -
                      0.06 * p -
                      (_heroReturn || _reduceMotion ? 0 : 0.04 * t),
                  child: Opacity(
                    opacity: 1 - t,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16 * math.max(p, t)),
                      child: HeroMode(
                        enabled: !_pullPop || _heroReturn,
                        child: child!,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        final stationary = Transform.translate(
          key: const ValueKey('image-surface-translation'),
          offset: Offset.zero,
          child: child,
        );
        if (_reduceMotion) return stationary;
        if (preview) {
          return FadeTransition(opacity: animation, child: stationary);
        }
        return SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: stationary,
        );
      },
    );
    return IOSBackGestureDetector(
      gestureWidth: 20,
      enabledCallback: () =>
          !isDismissing &&
          isCurrent &&
          !isFirst &&
          !willHandlePopInternally &&
          popGestureEnabled &&
          popDisposition != RoutePopDisposition.doNotPop &&
          animation.status == AnimationStatus.completed &&
          secondaryAnimation.status == AnimationStatus.dismissed &&
          !navigator!.userGestureInProgress,
      onStartPopGesture: () =>
          IOSBackGestureController(controller!, navigator!),
      child: preview ? SwipeRegionMarker(child: body) : body,
    );
  }
}

RectTween imageSurfaceRectTween(Rect? begin, Rect? end) =>
    RectTween(begin: begin, end: end);

PageRoute<T> imageSurfacePageRoute<T>({
  required WidgetBuilder builder,
  bool preview = false,
  bool materialFallback = false,
}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return ImageSurfaceRoute<T>(builder: builder, preview: preview);
  }
  return materialFallback
      ? MaterialPageRoute<T>(builder: builder)
      : AppPageRoute<T>(builder: builder);
}

Widget imageSurfaceHeroFlight(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext from,
  BuildContext to,
) => _imageFlight(animation, direction, from, to, 14);

Widget imageFavoriteHeroFlight(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext from,
  BuildContext to,
) => _imageFlight(animation, direction, from, to, 8);

Widget _imageFlight(
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext from,
  BuildContext to,
  double radius,
) {
  final route = ModalRoute.of(from);
  ui.Image? image = route is ImageSurfaceRoute ? route._flightImage : null;
  void find(Element e) {
    if (image != null) return;
    final w = e.widget;
    if (w is RawImage && w.image != null) image = w.image;
    e.visitChildren(find);
  }

  find(from as Element);
  if (image == null) find(to as Element);
  if (image == null) return (to.widget as Hero).child;
  final fromBox = from.findRenderObject() as RenderBox;
  final toBox = to.findRenderObject() as RenderBox;
  return _ImageFlight(
    image: image!.clone(),
    animation: animation,
    direction: direction,
    fromSize: fromBox.size,
    toSize: toBox.size,
    radius: radius,
  );
}

class _ImageFlight extends StatefulWidget {
  const _ImageFlight({
    required this.image,
    required this.animation,
    required this.direction,
    required this.fromSize,
    required this.toSize,
    required this.radius,
  });
  final ui.Image image;
  final Animation<double> animation;
  final HeroFlightDirection direction;
  final Size fromSize, toSize;
  final double radius;
  @override
  State<_ImageFlight> createState() => _ImageFlightState();
}

class _ImageFlightState extends State<_ImageFlight> {
  @override
  void didUpdateWidget(_ImageFlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) oldWidget.image.dispose();
  }

  @override
  void dispose() {
    widget.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.animation,
    builder: (context, _) {
      final pop = widget.direction == HeroFlightDirection.pop;
      final t = (pop ? 1 - widget.animation.value : widget.animation.value)
          .clamp(0.0, 1.0);
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius * (pop ? t : 1 - t)),
        child: CustomPaint(
          key: const ValueKey('image-surface-hero-flight'),
          painter: _ImageFlightPainter(
            widget.image,
            widget.fromSize,
            widget.toSize,
            pop,
            t,
          ),
          child: const SizedBox.expand(),
        ),
      );
    },
  );
}

class _ImageFlightPainter extends CustomPainter {
  _ImageFlightPainter(this.image, this.from, this.to, this.pop, this.t);
  final ui.Image image;
  final Size from, to;
  final bool pop;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    Rect crop(Size destination, BoxFit fit) => Alignment.center.inscribe(
      applyBoxFit(fit, imageSize, destination).source,
      Offset.zero & imageSize,
    );
    final source = crop(from, pop ? BoxFit.contain : BoxFit.cover);
    final target = crop(to, pop ? BoxFit.cover : BoxFit.contain);
    canvas.drawImageRect(
      image,
      Rect.lerp(source, target, t)!,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ImageFlightPainter old) =>
      old.image != image || old.t != t || old.from != from || old.to != to;
}
