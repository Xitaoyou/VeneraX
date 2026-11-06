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

class _PullDownToDismissState extends State<PullDownToDismiss> {
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

  void _cancel() {
    _pointer = null;
    _downward = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      _pointers.add(event.pointer);
      if (_pointers.length != 1 ||
          event.kind != PointerDeviceKind.touch ||
          !_enabled) {
        _cancel();
        return;
      }
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
    },
    onPointerUp: (event) async {
      final dismiss =
          event.pointer == _pointer &&
          _downward &&
          _enabled &&
          _distance.dy >= 100 &&
          _distance.dy > _distance.dx.abs() * 2;
      _pointers.remove(event.pointer);
      _cancel();
      if (!dismiss) return;
      _popping = true;
      try {
        await Navigator.of(context).maybePop();
      } finally {
        if (mounted) _popping = false;
      }
    },
    onPointerCancel: (event) {
      _pointers.remove(event.pointer);
      _cancel();
    },
    child: widget.child,
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
