import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native Material controls still own gestures, semantics, focus and callbacks.
/// This layer only adds visual feedback, never an extra activation handler.
class LookoutPressFeedback extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const LookoutPressFeedback({
    super.key,
    required this.child,
    this.enabled = true,
  });
  @override
  State<LookoutPressFeedback> createState() => _LookoutPressFeedbackState();

  static Widget buttonLayer(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final pressed =
        states.contains(WidgetState.pressed) &&
        !states.contains(WidgetState.disabled);
    return AnimatedScale(
      scale: pressed && !reduced ? .98 : 1,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

class _LookoutPressFeedbackState extends State<LookoutPressFeedback> {
  final Set<int> _pointers = {};
  bool _keyDown = false;
  bool get _enabled {
    if (!widget.enabled) return false;
    final child = widget.child;
    if (child is FloatingActionButton) return child.onPressed != null;
    if (child is ActionChip) return child.onPressed != null;
    if (child is InkWell) {
      return child.onTap != null || child.onLongPress != null;
    }

    if (child is ListTile) return child.enabled && child.onTap != null;
    return true;
  }

  void _release(int pointer) => setState(() => _pointers.remove(pointer));
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused && mounted) {
          setState(() {
            _pointers.clear();
            _keyDown = false;
          });
        }
      },
      onKeyEvent: (_, event) {
        if (event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          setState(() => _keyDown = _enabled && event is KeyDownEvent);
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        onPointerDown: (e) {
          if (_enabled) setState(() => _pointers.add(e.pointer));
        },
        onPointerUp: (e) => _release(e.pointer),
        onPointerCancel: (e) => _release(e.pointer),
        child: AnimatedScale(
          scale: _enabled && !reduced && (_pointers.isNotEmpty || _keyDown)
              ? .98
              : 1,
          duration: reduced ? Duration.zero : const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}
