// SPDX-License-Identifier: MIT
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';
import 'widgets.dart';

/// Asks for a line of text – a name – and returns it, or `null` when cancelled or left empty.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String confirm,
  String initial = '',
  String? label,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _AskText(title: title, confirm: confirm, initial: initial, label: label),
  );
  return result == null || result.isEmpty ? null : result;
}

/// The dialog of [askText]: it owns its field, which lives as long as the dialog – also while it fades out.
class _AskText extends StatefulWidget {
  const _AskText({required this.title, required this.confirm, required this.initial, this.label});

  final String title;
  final String confirm;
  final String initial;
  final String? label;

  @override
  State<_AskText> createState() => _AskTextState();
}

class _AskTextState extends State<_AskText> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const ValueKey('ask-text'),
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _done(),
        ),
      ),
      actions: [
        KButton(
          label: MaterialLocalizations.of(context).cancelButtonLabel,
          tone: KTone.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
        KButton(key: const ValueKey('ask-confirm'), label: widget.confirm, tone: KTone.primary, onPressed: _done),
      ],
    );
  }
}

/// Asks whether to go on – the confirming button in red when `danger` – and returns the answer.
Future<bool> confirmAction(
  BuildContext context, {
  required String text,
  required String confirm,
  bool danger = false,
}) async {
  final cancel = MaterialLocalizations.of(context).cancelButtonLabel;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: SizedBox(width: 360, child: Text(text, style: KText.body(context.k))),
      actions: [
        KButton(label: cancel, tone: KTone.quiet, onPressed: () => Navigator.of(context).pop(false)),
        KButton(
          key: const ValueKey('confirm-action'),
          label: confirm,
          tone: danger ? KTone.danger : KTone.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return sure ?? false;
}

/// A note to read, with one button to close it.
Future<void> showNote(BuildContext context, {required String text, required String close}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    content: SizedBox(width: 360, child: Text(text, style: KText.body(context.k))),
    actions: [
      KButton(
        key: const ValueKey('note-close'),
        label: close,
        tone: KTone.primary,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  ),
);

/// A menu at a point – of a right click or a long press – with an icon before every entry.
Future<T?> showPointMenu<T>(
  BuildContext context, {
  required Offset position,
  required List<(T value, IconData icon, String label, bool danger)> items,
}) {
  final k = context.k;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      for (final (value, icon, label, danger) in items)
        PopupMenuItem<T>(
          key: ValueKey('menu-$value'),
          value: value,
          height: KSize.control,
          child: Row(
            children: [
              Icon(icon, size: 16, color: danger ? k.error : k.muted),
              const SizedBox(width: 10),
              Text(label, style: KText.label(k).copyWith(color: danger ? k.error : k.text)),
            ],
          ),
        ),
    ],
  );
}
