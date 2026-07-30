import 'package:flutter/material.dart';

class FluiddCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final bool scrollable;
  final bool collapsible;
  final bool initiallyExpanded;

  const FluiddCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions,
    this.scrollable = true,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  @override
  State<FluiddCard> createState() => _FluiddCardState();
}

class _FluiddCardState extends State<FluiddCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          if (widget.collapsible)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.grey.shade400,
              ),
            ),
          Expanded(
            child: InkWell(
              onTap: widget.collapsible
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.subtitle!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (widget.actions != null) ...widget.actions!,
        ],
      ),
    );

    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: widget.child,
    );

    return Card(
      color: const Color(0xFF2C3034),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (!widget.collapsible || _expanded)
            widget.scrollable
                ? Flexible(child: SingleChildScrollView(child: body))
                : body,
        ],
      ),
    );
  }
}
