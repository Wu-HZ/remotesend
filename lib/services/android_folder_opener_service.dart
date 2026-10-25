import 'package:flutter/services.dart';

/// An Android activity that can handle the same folder URI as the existing
/// system "open with" action. The component is stored so future opens never
/// depend on Android's unreliable "Always" resolver choice.
class AndroidFolderOpener {
  final String component;
  final String label;

  /// PNG icon supplied by Android's PackageManager; absent if the app has none.
  final Uint8List? iconPng;

  const AndroidFolderOpener({
    required this.component,
    required this.label,
    this.iconPng,
  });
}

class SelectedFolderOpenerUnavailable implements Exception {
  const SelectedFolderOpenerUnavailable();
}

class AndroidFolderOpenerService {
  final MethodChannel _channel;

  const AndroidFolderOpenerService({
    MethodChannel channel = const MethodChannel('remote_send/folder_opener'),
  }) : _channel = channel;

  Future<List<AndroidFolderOpener>> available(String directory) async {
    final entries = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'available',
      {'path': directory},
    );
    return [
      for (final entry in entries ?? <Map<dynamic, dynamic>>[])
        if (entry['component'] is String && entry['label'] is String)
          AndroidFolderOpener(
            component: entry['component'] as String,
            label: entry['label'] as String,
            iconPng: entry['icon'] is Uint8List
                ? entry['icon'] as Uint8List
                : null,
          ),
    ];
  }

  Future<void> open(String directory, String component) async {
    try {
      final opened = await _channel.invokeMethod<bool>('open', {
        'path': directory,
        'component': component,
      });
      if (opened != true) throw const SelectedFolderOpenerUnavailable();
    } on PlatformException {
      throw const SelectedFolderOpenerUnavailable();
    } on MissingPluginException {
      throw const SelectedFolderOpenerUnavailable();
    }
  }
}
