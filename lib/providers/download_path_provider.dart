import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/server_config.dart';
import '../services/webdav_service.dart';
import '../services/download_path_service.dart';

final downloadSourceServiceProvider =
    Provider<WebDavService Function(ServerConfig)>((ref) {
      return (server) => WebDavService()..initializeWithServer(server);
    });

final downloadPathServiceProvider = Provider<DownloadPathService>((ref) {
  return DownloadPathService();
});

final openLocalDirectoryProvider = Provider<Future<bool> Function(String)>((
  ref,
) {
  return (path) async {
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    } else if (Platform.isAndroid) {
      const externalRoot = '/storage/emulated/0';
      final uriPath = path.startsWith('$externalRoot/') || path == externalRoot
          ? '/external${path.substring(externalRoot.length)}'
          : '/root$path';
      return launchUrl(
        Uri(
          scheme: 'content',
          host: 'com.remotesend.remote_send.fileprovider',
          path: uriPath,
        ),
        mode: LaunchMode.externalApplication,
      );
    } else {
      return false;
    }
    return true;
  };
});
