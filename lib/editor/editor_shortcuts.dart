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

  /// Document-level chords that should still run while a text field is focused
  /// (new / open / save / close tab).
  static bool _isDocumentChord(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.keyN ||
      key == LogicalKeyboardKey.keyO ||
      key == LogicalKeyboardKey.keyS ||
      key == LogicalKeyboardKey.keyW;

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
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.tab;
    }
    if (chord && !alt) {
      // Keep New/Open/Save/Close available while typing in a search box.
      if (_isDocumentChord(key)) return false;
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        return true;
      }
      // Defer every other Cmd/Ctrl(+Shift) letter and bracket chord so find,
      // rotate, duplicate, group, lock, bold, undo, etc. cannot steal keys
      // from the field (and so default text-editing shortcuts can run).
      if (key == LogicalKeyboardKey.bracketLeft ||
          key == LogicalKeyboardKey.bracketRight) {
        return true;
      }
      return key.keyId >= LogicalKeyboardKey.keyA.keyId &&
          key.keyId <= LogicalKeyboardKey.keyZ.keyId;
    }
    if (alt) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.tab) {
        return true;
      }
      return key.keyId >= LogicalKeyboardKey.keyA.keyId &&
          key.keyId <= LogicalKeyboardKey.keyZ.keyId;
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
