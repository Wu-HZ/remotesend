import 'dart:io';
import 'dart:ui' show Rect;
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
}

/// Persists window position and size via SharedPreferences.
/// Only active on desktop platforms (Windows, Linux, macOS).
class WindowService {
  static const String _keyX = 'window_x';
  static const String _keyY = 'window_y';
  static const String _keyWidth = 'window_width';
  static const String _keyHeight = 'window_height';
  static const String _keyIsMaximized = 'window_is_maximized';

  bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> save(WindowState state) async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    if (state.x != null) await prefs.setDouble(_keyX, state.x!);
    if (state.y != null) await prefs.setDouble(_keyY, state.y!);
    if (state.width != null) await prefs.setDouble(_keyWidth, state.width!);
    if (state.height != null) await prefs.setDouble(_keyHeight, state.height!);
    await prefs.setBool(_keyIsMaximized, state.isMaximized);
  }

  Future<WindowState?> load() async {
    if (!isSupported) return null;
    final prefs = await SharedPreferences.getInstance();

    final x = prefs.getDouble(_keyX);
    final y = prefs.getDouble(_keyY);
    final width = prefs.getDouble(_keyWidth);
    final height = prefs.getDouble(_keyHeight);

    if (x == null || y == null || width == null || height == null) {
      return null;
    }

    // Basic sanity check: reject positions that are off-screen
    if (x < -320 || y < -320 || width < 320 || height < 480) {
      return null;
    }

    final isMaximized = prefs.getBool(_keyIsMaximized) ?? false;

    return WindowState(
      x: x,
      y: y,
      width: width,
      height: height,
      isMaximized: isMaximized,
    );
  }
}
