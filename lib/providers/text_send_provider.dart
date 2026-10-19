import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_endpoint.dart';
import 'config_provider.dart';
import 'gotify_text_session_provider.dart';
import 'message_history_provider.dart';
import 'text_endpoint_provider.dart';
import 'webdav_provider.dart';

final textSendControllerProvider = Provider((ref) => TextSendController(ref));
final textSendingProvider = Provider<bool>((ref) {
  final endpoint = ref.watch(activeTextEndpointProvider);
  if (endpoint is GotifyTextEndpoint) {
    return ref.watch(gotifyTextSessionProvider).isSending;
  }
  if (endpoint is WebDavEndpoint) {
    return ref.watch(messageHistoryProvider).isSending;
  }
  return false;
});

class TextSendController {
  TextSendController(this._ref);
  final Ref _ref;
  Future<bool> send(String text) {
    final endpoint = _ref.read(activeTextEndpointProvider);
    if (endpoint is GotifyTextEndpoint) {
      return _ref.read(gotifyTextSessionProvider.notifier).send(text);
    }
    if (endpoint is WebDavEndpoint) {
      return _ref.read(messageHistoryProvider.notifier).sendMessage(text);
    }
    return Future.value(false);
  }

  Future<bool> retry(String id) {
    if (_ref.read(activeTextEndpointProvider) is! GotifyTextEndpoint) {
      return Future.value(false);
    }
    final message = _ref
        .read(gotifyTextSessionProvider)
        .messages
        .where((m) => m.id == id && m.isLocal)
        .firstOrNull;
    if (message == null) return Future.value(false);
    return _ref
        .read(gotifyTextSessionProvider.notifier)
        .send(message.content, retryId: id);
  }
}

final textEndpointActionsProvider = Provider((ref) => TextEndpointActions(ref));

class TextEndpointActions {
  TextEndpointActions(this._ref) {
    _ref.onDispose(() => _disposed = true);
  }
  final Ref _ref;
  bool _disposed = false;
  Future<bool> select(ServerEndpoint endpoint) async {
    if (_ref.read(configProvider).valueOrNull?.activeTextServerId ==
        endpoint.id) {
      return true;
    }
    final saved = await _ref
        .read(configProvider.notifier)
        .switchTextServer(endpoint.id);
    if (!saved || _disposed) return false;
    if (endpoint is WebDavEndpoint &&
        _ref.read(configProvider).valueOrNull?.activeTextServerId ==
            endpoint.id) {
      await _ref.read(textConnectionStatusProvider.notifier).testConnection();
      if (!_disposed &&
          _ref.read(configProvider).valueOrNull?.activeTextServerId ==
              endpoint.id) {
        await _ref.read(messageHistoryProvider.notifier).refresh();
      }
    }
    return true;
  }
}
