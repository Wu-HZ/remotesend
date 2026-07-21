import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class WindowState {
  final double? x;
  final double? y;
  final double? width;
  final double? height;
  final bool isMaximized;

  const WindowState({
    this.x,
    this.y,
    this.width,
    this.height,
    this.isMaximized = false,
  });

  Rect? get rect {
    if (x == null || y == null || width == null || height == null) return null;
    return Rect.fromLTWH(x!, y!, width!, height!);
  }

  factory WindowState.fromRect(Rect rect, {bool isMaximized = false}) {
    return WindowState(
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
      isMaximized: isMaximized,
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'isMaximized': isMaximized,
      };

  factory WindowState.fromJson(Map<String, dynamic> json) {
    return WindowState(
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      isMaximized: json['isMaximized'] == true,
    );
  }
}

/// Persists window position and size.
///
/// If a portable config.json exists next to the executable, stores
/// window state in window_state.json alongside it. Otherwise uses
/// SharedPreferences.
/// Only active on desktop platforms (Windows, Linux, macOS).
class WindowService {
  static const String _keyX = 'window_x';
  static const String _keyY = 'window_y';
  static const String _keyWidth = 'window_width';
  static const String _keyHeight = 'window_height';
  static const String _keyIsMaximized = 'window_is_maximized';

  bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Returns the path to window_state.json if portable mode is active.
  String get _portableStatePath {
    if (!isSupported) return '';
    final executableDir = p.dirname(Platform.resolvedExecutable);
    final configPath = p.join(executableDir, 'config.json');
    if (File(configPath).existsSync()) {
      return p.join(executableDir, 'window_state.json');
    }
    return '';
  }

  Future<void> save(WindowState state) async {
    if (!isSupported) return;

    final portablePath = _portableStatePath;
    if (portablePath.isNotEmpty) {
      try {
        await File(portablePath)
            .writeAsString(const JsonEncoder.withIndent('  ').convert(state.toJson()));
      } catch (_) {}
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (state.x != null) await prefs.setDouble(_keyX, state.x!);
    if (state.y != null) await prefs.setDouble(_keyY, state.y!);
    if (state.width != null) await prefs.setDouble(_keyWidth, state.width!);
    if (state.height != null) await prefs.setDouble(_keyHeight, state.height!);
    await prefs.setBool(_keyIsMaximized, state.isMaximized);
  }

  Future<WindowState?> load() async {
    if (!isSupported) return null;

    final portablePath = _portableStatePath;
    if (portablePath.isNotEmpty) {
      try {
        final file = File(portablePath);
        if (!file.existsSync()) return null;
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final state = WindowState.fromJson(json);
        if (_isValid(state)) return state;
      } catch (_) {}
      return null;
    }

    final prefs = await SharedPreferences.getInstance();

    final x = prefs.getDouble(_keyX);
    final y = prefs.getDouble(_keyY);
    final width = prefs.getDouble(_keyWidth);
    final height = prefs.getDouble(_keyHeight);

    if (x == null || y == null || width == null || height == null) {
      return null;
    }

    final isMaximized = prefs.getBool(_keyIsMaximized) ?? false;

    final state = WindowState(
      x: x,
      y: y,
      width: width,
      height: height,
      isMaximized: isMaximized,
    );
    return _isValid(state) ? state : null;
  }

  bool _isValid(WindowState state) {
    if (state.x == null || state.y == null ||
        state.width == null || state.height == null) {
      return false;
    }
    if (state.x! < -320 || state.y! < -320 ||
        state.width! < 320 || state.height! < 480) {
      return false;
    }
    return true;
  }
}
