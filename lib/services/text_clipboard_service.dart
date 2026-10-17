import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared clipboard access identifies app-originated copies, preventing received
/// text from being echoed back when temporary auto-send is enabled.
class TextClipboardService {
  String? _internalText;
  int _writeRevision = 0;
  bool _writing = false;

  Future<String?> readText() async {
    final revision = _writeRevision;
    final wasWriting = _writing;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    // A delayed read must not erase the marker of a newer app-originated copy.
    if (revision == _writeRevision &&
        !wasWriting &&
        !_writing &&
        text?.trim() != _internalText) {
      _internalText = null;
    }
    return text;
  }

  bool isInternalText(String text) => text.trim() == _internalText;

  Future<void> writeText(String text) async {
    final previous = _internalText;
    final revision = ++_writeRevision;
    _writing = true;
    _internalText = text.trim();
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      if (revision == _writeRevision) _internalText = previous;
      rethrow;
    } finally {
      if (revision == _writeRevision) _writing = false;
    }
  }
}

final textClipboardServiceProvider = Provider<TextClipboardService>(
  (ref) => TextClipboardService(),
);
