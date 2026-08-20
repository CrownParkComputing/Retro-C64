import 'package:flutter/foundation.dart';

/// The two pieces of in-game UI state that are set from OUTSIDE the emulator
/// view: whether the C64 keyboard is up, and whether the on-screen controls
/// are being dragged around.
///
/// They live here rather than inside EmulatorScreen because the buttons that
/// toggle them sit in the workbench's shell, below the content panel, not
/// over the picture -- the panel's border is the edge of the machine, and
/// chrome belongs outside it. Two widgets in different subtrees have to agree
/// on one answer, so the answer cannot be private to either of them.
class EmulatorUiState extends ChangeNotifier {
  bool _keyboardVisible = false;
  bool _editingLayout = false;

  bool get keyboardVisible => _keyboardVisible;
  bool get editingLayout => _editingLayout;

  set keyboardVisible(bool value) {
    if (_keyboardVisible == value) return;
    _keyboardVisible = value;
    notifyListeners();
  }

  set editingLayout(bool value) {
    if (_editingLayout == value) return;
    _editingLayout = value;
    notifyListeners();
  }

  void toggleKeyboard() => keyboardVisible = !_keyboardVisible;
  void toggleLayoutEditing() => editingLayout = !_editingLayout;

  /// Leaving a session must not leave the next one in a mode the user did
  /// not ask for -- an in-progress layout edit especially, which disables
  /// every control it is editing.
  void reset() {
    if (!_keyboardVisible && !_editingLayout) return;
    _keyboardVisible = false;
    _editingLayout = false;
    notifyListeners();
  }
}
