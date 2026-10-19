import 'package:flutter/material.dart';
import '../theme/checkmate_theme.dart';

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fades and lifts [child] in once, staggered by [index] for lists.
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  final double offset;

  const Reveal(
      {super.key, required this.child, this.index = 0, this.offset = 24});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  // Stagger is the idle head of one animation (no timers); capped so long
  // lists don't keep the user waiting.
  late final int _delayMs = 55 * widget.index.clamp(0, 8);
  late final int _totalMs = CheckMateTheme.slow.inMilliseconds + _delayMs;
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: Duration(milliseconds: _totalMs));
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(_delayMs / _totalMs, 1, curve: CheckMateTheme.emphasized),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.status != AnimationStatus.dismissed) return;
    if (_reduceMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Shrinks [child] slightly while a finger is down, for tactile press feedback.
/// Does not take part in gestures, so the child's own taps still work.
class Pressable extends StatefulWidget {
  final Widget child;
  final double scale;

  const Pressable({super.key, required this.child, this.scale = 0.97});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !_reduceMotion(context) ? widget.scale : 1,
        duration: CheckMateTheme.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
