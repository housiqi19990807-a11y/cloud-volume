// Reports the child's unconstrained layout size so window-fit logic can see
// true content height even when the parent (Expanded / short window) clamps us.

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Wraps [child] and invokes [onChange] with the child's size after layout
/// under loosened height constraints (maxHeight: infinity).
///
/// Important: report the *child* size, not [size] of this render object.
/// Parents like [Expanded] force this box short; using our own size would
/// under-measure and clip buttons / padding when resizing the OS window.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({
    super.key,
    required this.onChange,
    this.contentWidth,
    required super.child,
  });

  final ValueChanged<Size> onChange;

  /// When set, child is laid out at this exact width (form columns).
  final double? contentWidth;

  @override
  RenderMeasureSize createRenderObject(BuildContext context) {
    return RenderMeasureSize(onChange: onChange, contentWidth: contentWidth);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMeasureSize renderObject,
  ) {
    renderObject
      ..onChange = onChange
      ..contentWidth = contentWidth;
  }
}

/// Public render object for [MeasureSize].
class RenderMeasureSize extends RenderProxyBox {
  RenderMeasureSize({
    required this.onChange,
    this.contentWidth,
  });

  ValueChanged<Size> onChange;
  double? contentWidth;

  Size? _oldReported;
  Size? _pendingReported;
  bool _callbackScheduled = false;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }

    final width = contentWidth;
    final childConstraints = BoxConstraints(
      minWidth: width ?? 0,
      maxWidth: width ??
          (constraints.hasBoundedWidth && constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : double.infinity),
      minHeight: 0,
      maxHeight: double.infinity,
    );
    child.layout(childConstraints, parentUsesSize: true);
    final reported = child.size;
    if (!reported.width.isFinite ||
        !reported.height.isFinite ||
        reported.width <= 0 ||
        reported.height <= 0) {
      // Fall back to parent-clamped size rather than feeding infinity into
      // window-fit math (can happen with mainAxisSize.max + infinite height).
      size = constraints.constrain(const Size(0, 0));
      return;
    }

    // Occupy only what the parent allows so we don't force overflow painting
    // before the OS window has been resized to match [reported].
    size = constraints.constrain(reported);
    _scheduleReport(reported);
  }

  void _scheduleReport(Size reported) {
    if (_oldReported == reported) return;
    _oldReported = reported;
    _pendingReported = reported;
    if (_callbackScheduled) return;
    _callbackScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _callbackScheduled = false;
      final next = _pendingReported;
      _pendingReported = null;
      if (next != null) {
        onChange(next);
      }
    });
  }
}
