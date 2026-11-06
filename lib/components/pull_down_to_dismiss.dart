import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/image_surface_route.dart';

/// Raw pointer observation coexists with PhotoView's scale recognizer. The
/// dedicated route animates the whole page; this widget never moves an image.
class PullDownToDismiss extends StatefulWidget {
  const PullDownToDismiss({
    super.key,
    required this.enabled,
    required this.child,
    this.heroTag,
  });
  final bool Function() enabled;
  final Object? Function()? heroTag;
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
  ImageSurfaceRoute<dynamic>? _route;

  bool get _enabled =>
      !_popping &&
      widget.enabled() &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  void _cancel() {
    _pointer = null;
    _downward = false;
    final route = _route;
    _route = null;
    route?.cancelPull();
  }

  @override
  void dispose() {
    _route?.cancelPull();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if (_popping) return;
      _pointers.add(event.pointer);
      final route = ModalRoute.of(context);
      if (_pointers.length != 1 ||
          event.kind != PointerDeviceKind.touch ||
          !_enabled ||
          route is! ImageSurfaceRoute ||
          route.isDismissing) {
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
          _cancel();
          return;
        }
        final route = ModalRoute.of(context);
        if (route is! ImageSurfaceRoute || !route.beginPull(context)) {
          _cancel();
          return;
        }
        _route = route;
        _downward = true;
      }
      if (_downward) _route?.updatePull(_distance.dy);
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
      if (!dismiss) {
        _cancel();
        return;
      }
      final route = _route;
      _pointer = null;
      _downward = false;
      _route = null;
      _popping = true;
      try {
        await route?.finishPull(widget.enabled, widget.heroTag?.call());
      } finally {
        if (mounted) _popping = false;
      }
    },
    onPointerCancel: (event) {
      if (_popping) return;
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
    this.heroTag,
  });

  final bool Function() canDismiss;
  final Object? Function()? heroTag;
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
    heroTag: widget.heroTag,
    child: widget.builder(_controller),
  );
}
