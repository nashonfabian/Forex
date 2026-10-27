import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/rows.dart';

void snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Turns the database's rule messages into plain language.
String friendlyError(Object e) {
  final t = '$e';
  if (t.contains('hypothesis_locked')) {
    return 'The hypothesis is locked and can no longer be changed. Add an addendum instead.';
  }
  if (t.contains('hypothesis_required')) return 'Write a hypothesis before locking it.';
  if (t.contains('outcome_requires_locked_hypothesis')) {
    return 'Lock the hypothesis before recording the outcome.';
  }
  return t.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: destructive ? TextStyle(color: Theme.of(ctx).colorScheme.error) : null),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Lets the user choose one record from a list. Returns null if cancelled.
Future<Rec?> pickRec(
  BuildContext context, {
  required String title,
  required List<Rec> items,
  required String Function(Rec) label,
  String Function(Rec)? subtitle,
}) {
  return showDialog<Rec>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: items.isEmpty
            ? const Text('Nothing to choose from yet.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(label(items[i]), maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: subtitle == null ? null : Text(subtitle(items[i])),
                  onTap: () => Navigator.pop(ctx, items[i]),
                ),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
    ),
  );
}

Future<DateTime?> pickDate(BuildContext context, DateTime initial) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
}

Future<DateTime?> pickDateTime(BuildContext context, DateTime initial) async {
  final date = await pickDate(context, initial);
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}

/// A label + value line used in read-only views. Hidden when the value is empty.
class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value!),
        ],
      ),
    );
  }
}

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int? minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        textCapitalization: TextCapitalization.sentences,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }
}

/// Single choice shown as chips. Tapping the selected chip clears it when [allowClear].
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.allowClear = true,
    this.enabled = true,
  });

  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(pretty(o)),
                  selected: value == o,
                  onSelected: enabled
                      ? (selected) => onChanged(selected ? o : (allowClear ? null : value))
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A text field with quick-fill chips (for example instruments).
class SuggestField extends StatelessWidget {
  const SuggestField({
    super.key,
    required this.controller,
    required this.label,
    required this.suggestions,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            enabled: enabled,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in suggestions)
                ActionChip(
                  label: Text(s),
                  onPressed: enabled ? () => controller.text = s : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Date / date-time field that opens a picker when tapped.
class PickerField extends StatelessWidget {
  const PickerField({super.key, required this.label, required this.text, required this.onTap, this.enabled = true});

  final String label;
  final String text;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          child: Text(text.isEmpty ? 'Tap to choose' : text),
        ),
      ),
    );
  }
}

List<String> splitTags(String text) =>
    text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

/// Trimmed text, or null when empty (so empty fields are stored as NULL).
String? emptyToNull(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}
