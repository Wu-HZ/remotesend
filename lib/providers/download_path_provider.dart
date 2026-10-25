import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/server_config.dart';
import '../providers/config_provider.dart';
import '../services/android_folder_opener_service.dart';
import '../services/webdav_service.dart';
import '../services/download_path_service.dart';

final downloadSourceServiceProvider =
    Provider<WebDavService Function(ServerConfig)>((ref) {
      return (server) => WebDavService()..initializeWithServer(server);
    });

final downloadPathServiceProvider = Provider<DownloadPathService>((ref) {
  return DownloadPathService();
});

final androidFolderOpenerSupportedProvider = Provider<bool>(
  (ref) => Platform.isAndroid,
);

final androidFolderOpenerServiceProvider = Provider<AndroidFolderOpenerService>(
  (ref) => const AndroidFolderOpenerService(),
);

final openLocalDirectoryProvider = Provider<Future<bool> Function(String)>((
  ref,
) {
  return (path) async {
    if (ref.read(androidFolderOpenerSupportedProvider)) {
      final component =
          ref.read(configProvider).valueOrNull?.androidFolderOpenerComponent ??
          '';
      if (component.isNotEmpty) {
        await ref
            .read(androidFolderOpenerServiceProvider)
            .open(path, component);
        return true;
      }
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
    } else if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    } else {
      return false;
    }
    return true;
  };
});
