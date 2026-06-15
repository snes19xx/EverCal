/// components.dart
///
/// Contains reusable UI widgets like buttons, the event card, and the view switcher.
/// i.e. ExpressiveButton, BouncyButton, EventCard, and ViewSwitcher.

import 'package:flutter/material.dart';
import 'models.dart';
import 'utils.dart'; // for fmtTime

// Button based on M3 expressive guidelines
class ExpressiveButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final bool isSelected;
  final double size;
  final BorderSide side;

  const ExpressiveButton({
    super.key,
    required this.child,
    this.onTap,
    required this.color,
    this.isSelected = false,
    this.size = 50,
    this.side = BorderSide.none,
  });

  @override
  State<ExpressiveButton> createState() => _ExpressiveButtonState();
}

class _ExpressiveButtonState extends State<ExpressiveButton> {
  bool _isPressed = false;

  late ShapeBorder _idleShape;
  late ShapeBorder _morphShape;

  static const BoxShadow _inactiveShadow = BoxShadow(
    color: Colors.transparent,
    blurRadius: 6,
    spreadRadius: -1,
    offset: Offset(0, 3),
  );

  static const BoxShadow _activeShadow = BoxShadow(
    color: Color(0x26000000),
    blurRadius: 6,
    spreadRadius: -1,
    offset: Offset(0, 3),
  );

  @override
  void initState() {
    super.initState();
    _rebuildShapes();
  }

  @override
  void didUpdateWidget(covariant ExpressiveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.side != widget.side) {
      _rebuildShapes();
    }
  }

  void _rebuildShapes() {
    _idleShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: widget.side,
    );

    _morphShape = StarBorder(
      points: 8,
      innerRadiusRatio: 0.85,
      pointRounding: 0.5,
      valleyRounding: 0.5,
      side: widget.side,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shape = _isPressed ? _morphShape : _idleShape;
    final shadow =
        (_isPressed || widget.isSelected) ? _activeShadow : _inactiveShadow;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        width: widget.size,
        height: widget.size,
        decoration: ShapeDecoration(
          color: widget.color,
          shape: shape,
          shadows: [shadow],
        ),
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

// Bouncy button effect for event cards in week view
class BouncyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const BouncyButton({super.key, required this.child, required this.onTap});

  @override
  State<BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<BouncyButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90), // Quick, snappy duration
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: widget.child,
        ),
      ),
    );
  }
}

class ViewSwitcher extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool isMonthView;
  final bool compact;
  final VoidCallback onTap;
  final ThemeData theme;

  const ViewSwitcher({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isMonthView,
    required this.compact,
    required this.onTap,
    required this.theme,
  });

  @override
  State<ViewSwitcher> createState() => _ViewSwitcherState();
}

class _ViewSwitcherState extends State<ViewSwitcher> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final titleStyle = widget.compact
        ? widget.theme.textTheme.headlineMedium
        : widget.theme.textTheme.displayMedium;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.theme.colorScheme.onSurface.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: titleStyle?.copyWith(
                      height: 1.0, 
                    ),
                  ),
                  Text(
                    widget.subtitle,
                    style: widget.theme.textTheme.titleMedium?.copyWith(
                      color: widget.theme.colorScheme.onSurface.withOpacity(0.5),
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: widget.isMonthView ? 0 : 0.5,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutBack,
                child: Icon(
                  Icons.arrow_drop_down_rounded,
                  size: widget.compact ? 32 : 42,
                  color: _isHovered
                      ? widget.theme.colorScheme.primary
                      : widget.theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EventCard extends StatefulWidget {
  final CalendarEvent event;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  const EventCard(
      {super.key, required this.event, required this.onDelete, this.onEdit});

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  bool _expanded = false;

  Color _getRandomColor(String title) {
    const colors = [
      Color(0xFFE67E80), // Red
      Color(0xFFE69875), // Orange
      Color(0xFFDBBC7F), // Yellow
      Color(0xFFA7C080), // Green
      Color(0xFF83C092), // Mint 
      Color(0xFF7FBBB3), // Teal
      Color(0xFF7FB4CA), // Lavender 
      Color(0xFF938AA9), // Purple
      Color(0xFFD699B6), // Sakura
      Color(0xFF7A8490), // Slate
    ];
    return colors[title.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getRandomColor(widget.event.title);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            splashColor: color.withOpacity(0.3),
            highlightColor: color.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.event.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                              widget.event.allDay
                                  ? 'All day'
                                  : '${fmtTime.format(widget.event.startTime)} - ${fmtTime.format(widget.event.endTime)}',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Divider(
                            color: theme.colorScheme.outline.withOpacity(0.1)),
                        const SizedBox(height: 8),
                        if (widget.event.location != null &&
                            widget.event.location!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_outlined,
                                    size: 16, color: color),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(widget.event.location!,
                                        style: TextStyle(
                                            color: theme.colorScheme
                                                .onSurfaceVariant))),
                              ],
                            ),
                          ),
                        if (widget.event.description != null &&
                            widget.event.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.notes, size: 16, color: color),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(widget.event.description!,
                                        style: TextStyle(
                                            color: theme.colorScheme
                                                .onSurfaceVariant))),
                              ],
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (widget.onEdit != null)
                              TextButton.icon(
                                onPressed: widget.onEdit,
                                icon: Icon(Icons.edit_outlined,
                                    size: 18, color: theme.colorScheme.primary),
                                label: Text('Edit',
                                    style: TextStyle(
                                        color: theme.colorScheme.primary)),
                              ),
                            TextButton.icon(
                              onPressed: widget.onDelete,
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: theme.colorScheme.error),
                              label: Text('Delete',
                                  style: TextStyle(
                                      color: theme.colorScheme.error)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    crossFadeState: _expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}