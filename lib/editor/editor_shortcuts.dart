import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// App-level shortcut host like [CallbackShortcuts], but does not consume
/// keys that text fields need when an [EditableText] owns primary focus.
///
/// [CallbackShortcuts] always returns [KeyEventResult.handled] when an
/// activator matches — even if the callback no-ops — which blocks
/// [WidgetsApp]'s default text-editing shortcuts (Backspace, arrows, …)
/// from reaching the field.
class EditorCallbackShortcuts extends StatelessWidget {
  const EditorCallbackShortcuts({
    super.key,
    required this.bindings,
    required this.isEditableTextFocused,
    required this.child,
  });

  final Map<ShortcutActivator, VoidCallback> bindings;
  final bool Function() isEditableTextFocused;
  final Widget child;

  /// Keys that must bubble to the focused text field / default editing
  /// shortcuts instead of being claimed by the diagram editor.
  @visibleForTesting
  static bool isTextEditingShortcut(KeyEvent event) {
    final key = event.logicalKey;
    final hw = HardwareKeyboard.instance;
    final chord = hw.isControlPressed || hw.isMetaPressed;
    final alt = hw.isAltPressed;
    if (!chord && !alt) {
      return key == LogicalKeyboardKey.backspace ||
          key == LogicalKeyboardKey.delete ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.tab;
    }
    // Keep system clipboard / select-all working inside text fields.
    if (chord && !alt) {
      return key == LogicalKeyboardKey.keyA ||
          key == LogicalKeyboardKey.keyC ||
          key == LogicalKeyboardKey.keyV ||
          key == LogicalKeyboardKey.keyX;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (isEditableTextFocused() && isTextEditingShortcut(event)) {
          return KeyEventResult.ignored;
        }
        var result = KeyEventResult.ignored;
        for (final activator in bindings.keys) {
          if (activator.accepts(event, HardwareKeyboard.instance)) {
            bindings[activator]!.call();
            result = KeyEventResult.handled;
          }
        }
        return result;
      },
      child: child,
    );
  }
}
