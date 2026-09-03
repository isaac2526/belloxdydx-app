import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/tokens.dart';
import '../core/theme/typography.dart';
import 'motion.dart';

/// ============================================================
/// CONTROLS
/// Premium buttons with real loading states, fields that explain
/// themselves, and dropdowns that feel native on touch.
/// ============================================================

enum BxButtonKind { primary, secondary, ghost, danger }

class BxButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BxButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final bool large;
  final String? loadingLabel;

  const BxButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = BxButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.large = false,
    this.loadingLabel,
  });

  const BxButton.secondary(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.large = false,
    this.loadingLabel,
  }) : kind = BxButtonKind.secondary;

  const BxButton.ghost(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.large = false,
    this.loadingLabel,
  }) : kind = BxButtonKind.ghost;

  const BxButton.danger(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.large = false,
    this.loadingLabel,
  }) : kind = BxButtonKind.danger;

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final disabled = onPressed == null || loading;

    late final Color bg, fg, bd;
    switch (kind) {
      case BxButtonKind.primary:
        bg = c.gold;
        fg = const Color(0xFF241A00);
        bd = c.gold;
      case BxButtonKind.secondary:
        bg = c.surface;
        fg = c.ink;
        bd = c.lineStrong;
      case BxButtonKind.ghost:
        bg = Colors.transparent;
        fg = c.inkSoft;
        bd = Colors.transparent;
      case BxButtonKind.danger:
        bg = c.dangerTint;
        fg = c.danger;
        bd = c.danger.withValues(alpha: 0.4);
    }

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          Padding(
            padding: const EdgeInsets.only(right: BxSpace.xs),
            child: SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(fg),
              ),
            ),
          )
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: BxSpace.xs),
            child: Icon(icon, size: large ? 19 : 17, color: fg),
          ),
        Flexible(
          child: Text(
            loading ? (loadingLabel ?? label) : label,
            style: BxType.label(fg).copyWith(fontSize: large ? 15 : 14),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: BxScaleTap(
        onTap: disabled ? null : onPressed,
        scale: 0.965,
        child: AnimatedContainer(
          duration: BxDuration.fast,
          padding: EdgeInsets.symmetric(
            horizontal: large ? BxSpace.xl : BxSpace.lg,
            vertical: large ? BxSpace.md : BxSpace.sm + 2,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(BxRadius.sm),
            border: Border.all(color: bd),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// A labelled text field with helper and error slots that never shift
/// the layout when they appear.
class BxField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? error;
  final Widget? suffix;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final String? autofillHint;
  final int maxLines;
  final int? maxLength;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization capitalization;
  final TextAlign textAlign;
  final TextStyle? style;

  const BxField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.error,
    this.suffix,
    this.prefix,
    this.keyboardType,
    this.formatters,
    this.autofillHint,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.capitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final showError = error != null && error!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: BxType.eyebrow(c.muted)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          autofocus: autofocus,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          autofillHints: autofillHint == null ? null : [autofillHint!],
          maxLines: maxLines,
          maxLength: maxLength,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textCapitalization: capitalization,
          textAlign: textAlign,
          style: style ?? BxType.body(c.ink),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefix,
            suffixIcon: suffix,
            counterText: '',
            errorText: null,
            enabledBorder: showError
                ? OutlineInputBorder(
                    borderRadius: BxRadius.control,
                    borderSide: BorderSide(color: c.danger),
                  )
                : null,
          ),
        ),
        AnimatedSize(
          duration: BxDuration.fast,
          alignment: Alignment.topLeft,
          child: (showError || (helper != null && helper!.isNotEmpty))
              ? Padding(
                  padding: const EdgeInsets.only(top: 5, left: 2),
                  child: Text(
                    showError ? error! : helper!,
                    style: BxType.tiny(showError ? c.danger : c.muted),
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// Password field with a visibility toggle.
class BxPasswordField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? error;
  final String? autofillHint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const BxPasswordField({
    super.key,
    this.label = 'Password',
    this.controller,
    this.hint,
    this.helper,
    this.error,
    this.autofillHint,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<BxPasswordField> createState() => _BxPasswordFieldState();
}

class _BxPasswordFieldState extends State<BxPasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final showError = widget.error != null && widget.error!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label.toUpperCase(), style: BxType.eyebrow(c.muted)),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          obscureText: _hidden,
          autofillHints:
              widget.autofillHint == null ? null : [widget.autofillHint!],
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: BxType.body(c.ink),
          decoration: InputDecoration(
            hintText: widget.hint ?? '••••••••',
            enabledBorder: showError
                ? OutlineInputBorder(
                    borderRadius: BxRadius.control,
                    borderSide: BorderSide(color: c.danger),
                  )
                : null,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hidden = !_hidden),
              icon: Icon(
                _hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
                color: c.muted,
              ),
              tooltip: _hidden ? 'Show password' : 'Hide password',
            ),
          ),
        ),
        AnimatedSize(
          duration: BxDuration.fast,
          alignment: Alignment.topLeft,
          child: (showError ||
                  (widget.helper != null && widget.helper!.isNotEmpty))
              ? Padding(
                  padding: const EdgeInsets.only(top: 5, left: 2),
                  child: Text(
                    showError ? widget.error! : widget.helper!,
                    style: BxType.tiny(showError ? c.danger : c.muted),
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// Debounced search field. Appears in lists only when there is enough to
/// search, matching the website's rule.
class BxSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final Duration debounce;
  final TextEditingController? controller;

  const BxSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 180),
    this.controller,
  });

  @override
  State<BxSearchField> createState() => _BxSearchFieldState();
}

class _BxSearchFieldState extends State<BxSearchField> {
  late final TextEditingController _c =
      widget.controller ?? TextEditingController();
  Timer? _t;
  bool _hasText = false;

  @override
  void dispose() {
    _t?.cancel();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _hasText = v.isNotEmpty);
    _t?.cancel();
    _t = Timer(widget.debounce, () => widget.onChanged(v));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return TextField(
      controller: _c,
      onChanged: _onChanged,
      style: BxType.body(c.ink),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: Icon(Icons.search_rounded, size: 19, color: c.muted),
        suffixIcon: _hasText
            ? IconButton(
                tooltip: 'Clear',
                icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                onPressed: () {
                  _c.clear();
                  _onChanged('');
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: BxSpace.sm, vertical: BxSpace.sm),
      ),
    );
  }
}

/// A dropdown that opens a bottom sheet on touch — far better than a
/// native menu on a phone, and it can show a subtitle per option.
class BxDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<BxOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? hint;
  final bool enabled;
  final IconData? icon;

  const BxDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
    this.enabled = true,
    this.icon,
  });

  Future<void> _open(BuildContext context) async {
    final c = context.bx;
    final picked = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    BxSpace.lg, BxSpace.xs, BxSpace.lg, BxSpace.sm),
                child: Text(label, style: BxType.h3(c.ink)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(
                      BxSpace.sm, 0, BxSpace.sm, BxSpace.md),
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (_, i) {
                    final o = options[i];
                    final sel = o.value == value;
                    return ListTile(
                      dense: true,
                      selected: sel,
                      selectedTileColor: c.goldTint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BxRadius.sm),
                      ),
                      leading: o.icon == null
                          ? null
                          : Icon(o.icon,
                              size: 19, color: sel ? c.goldDeep : c.muted),
                      title: Text(o.label,
                          style: sel
                              ? BxType.bodyStrong(c.goldDeep)
                              : BxType.body(c.ink)),
                      subtitle: o.subtitle == null
                          ? null
                          : Text(o.subtitle!, style: BxType.tiny(c.muted)),
                      trailing: sel
                          ? Icon(Icons.check_rounded,
                              size: 19, color: c.goldDeep)
                          : null,
                      onTap: () => Navigator.pop(ctx, o.value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final current = options.where((o) => o.value == value).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: BxType.eyebrow(c.muted)),
        const SizedBox(height: 6),
        BxScaleTap(
          onTap: enabled ? () => _open(context) : null,
          scale: 0.985,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: BxSpace.md, vertical: BxSpace.sm + 2),
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BxRadius.control,
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: c.muted),
                  const SizedBox(width: BxSpace.xs),
                ],
                Expanded(
                  child: Text(
                    current?.label ?? hint ?? 'Select',
                    style: current == null
                        ? BxType.body(c.muted)
                        : BxType.body(c.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.expand_more_rounded, size: 20, color: c.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BxOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  const BxOption(this.value, this.label, {this.subtitle, this.icon});
}

/// A compact segmented control for two or three mutually exclusive modes.
class BxSegmented<T> extends StatelessWidget {
  final T value;
  final List<BxOption<T>> options;
  final ValueChanged<T> onChanged;

  const BxSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(BxRadius.sm),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final sel = o.value == value;
          return Flexible(
            child: BxScaleTap(
              onTap: () => onChanged(o.value),
              scale: 0.96,
              selected: sel,
              child: AnimatedContainer(
                duration: BxDuration.fast,
                padding: const EdgeInsets.symmetric(
                    horizontal: BxSpace.md, vertical: BxSpace.xs),
                decoration: BoxDecoration(
                  color: sel ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(BxRadius.xs),
                  border: Border.all(
                      color: sel ? c.gold.withValues(alpha: 0.5) : Colors.transparent),
                ),
                child: Text(
                  o.label,
                  textAlign: TextAlign.center,
                  style: sel
                      ? BxType.smallStrong(c.goldDeep)
                      : BxType.small(c.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// The gate students meet on locked content. Explains, then offers the
/// one action that opens it.
Future<void> showActivationGate(BuildContext context, VoidCallback onActivate) {
  final c = context.bx;
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.vpn_key_rounded, color: c.goldDeep, size: 30),
      title: const Text('Activation needed'),
      content: Text(
        'You are in preview mode. Your personal activation key opens every '
        'note, video, question and test on Belloxdydx.',
        style: BxType.body(c.inkSoft),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        BxButton.ghost('Keep looking around',
            onPressed: () => Navigator.pop(ctx)),
        BxButton('Activate', onPressed: () {
          Navigator.pop(ctx);
          onActivate();
        }),
      ],
    ),
  );
}

/// A confirm dialog with a named destructive action.
Future<bool> bxConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final c = context.bx;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message, style: BxType.body(c.inkSoft)),
      actions: [
        BxButton.ghost(cancelLabel, onPressed: () => Navigator.pop(ctx, false)),
        destructive
            ? BxButton.danger(confirmLabel,
                onPressed: () => Navigator.pop(ctx, true))
            : BxButton(confirmLabel, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return r ?? false;
}
