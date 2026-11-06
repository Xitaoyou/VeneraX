import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:venera/foundation/app.dart';

/// Observes the same pointer stream as PhotoView without competing with its
/// scale recognizer. A parent vertical GestureDetector cannot reliably do this:
/// PhotoView wins that arena even when its image is at the initial fit scale.
class PullDownToDismiss extends StatefulWidget {
  const PullDownToDismiss({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool Function() enabled;
  final Widget child;

  @override
  State<PullDownToDismiss> createState() => _PullDownToDismissState();
}

class _PullDownToDismissState extends State<PullDownToDismiss>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  Duration get _duration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 180);

  void _restore() {
    if (_offset.value == 0) return;
    _offset.animateTo(0, duration: _duration, curve: Curves.easeOutCubic);
  }

  final _pointers = <int>{};
  int? _pointer;
  Offset _origin = Offset.zero;
  Offset _distance = Offset.zero;
  bool _downward = false;
  bool _popping = false;

  bool get _enabled =>
      !_popping &&
      widget.enabled() &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  void _cancel({bool restore = true}) {
    _pointer = null;
    _downward = false;
    if (restore) _restore();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if (_popping) return;
      _pointers.add(event.pointer);
      if (_pointers.length != 1 ||
          event.kind != PointerDeviceKind.touch ||
          !_enabled) {
        _cancel();
        return;
      }
      _offset.stop();
      _offset.value = 0;
      _pointer = event.pointer;
      _origin = event.position;
      _distance = Offset.zero;
      _downward = false;
    },
    onPointerMove: (event) {
      if (event.pointer != _pointer) return;
      if (!_enabled) {
        _cancel();
        return;
      }
      _distance = event.position - _origin;
      if (!_downward && _distance.distance >= 18) {
        if (_distance.dy <= _distance.dx.abs() * 1.5) {
          _cancel(); // Horizontal paging or an upward drag stays that gesture.
        } else {
          _downward = true;
        }
      }
      if (_downward) {
        _offset.value =
            (_distance.dy - 18).clamp(0.0, MediaQuery.sizeOf(context).height) *
            0.8;
      }
    },
    onPointerUp: (event) async {
      if (_popping) return;
      final dismiss =
          event.pointer == _pointer &&
          _downward &&
          _enabled &&
          _distance.dy >= 100 &&
          _distance.dy > _distance.dx.abs() * 2;
      _pointers.remove(event.pointer);
      _cancel(restore: false);
      if (!dismiss) {
        _restore();
        return;
      }
      _popping = true;
      final route = ModalRoute.of(context)!;
      await _offset
          .animateTo(
            MediaQuery.sizeOf(context).height,
            duration: _duration,
            curve: Curves.easeOutCubic,
          )
          .orCancel
          .catchError((Object _) {});
      if (!mounted) return;
      // Recheck the live policy after the exit animation, including a dialog
      // opened while settling. maybePop still honors the route's PopScope.
      if (widget.enabled() && route.isCurrent) {
        await Navigator.of(context).maybePop();
      }
      if (mounted && route.isCurrent) {
        _popping = false;
        _restore();
      }
    },
    onPointerCancel: (event) {
      if (_popping) return;
      _pointers.remove(event.pointer);
      _cancel();
    },
    child: AnimatedBuilder(
      animation: _offset,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final progress = (_offset.value / MediaQuery.sizeOf(context).height)
            .clamp(0.0, 1.0);
        return Transform.translate(
          key: const ValueKey('pull-down-translation'),
          offset: Offset(0, _offset.value),
          transformHitTests: false,
          child: Transform.scale(
            scale: 1 - progress * 0.06,
            child: Opacity(opacity: 1 - progress, child: child),
          ),
        );
      },
    ),
  );
}

bool isPhotoViewZoomed(PhotoViewController? controller) {
  final scale = controller?.scale;
  final initial = controller?.getInitialScale?.call();
  return scale != null && initial != null && scale > initial * 1.01;
}

/// Owns a preview's controller so dismissal uses its real fit scale, not 1.0.
class DismissiblePhotoSurface extends StatefulWidget {
  const DismissiblePhotoSurface({
    super.key,
    required this.canDismiss,
    required this.builder,
  });

  final bool Function() canDismiss;
  final Widget Function(PhotoViewController controller) builder;

  @override
  State<DismissiblePhotoSurface> createState() =>
      _DismissiblePhotoSurfaceState();
}

class _DismissiblePhotoSurfaceState extends State<DismissiblePhotoSurface> {
  final _controller = PhotoViewController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PullDownToDismiss(
    enabled: () =>
        App.isIOS && widget.canDismiss() && !isPhotoViewZoomed(_controller),
    child: widget.builder(_controller),
  );
}
