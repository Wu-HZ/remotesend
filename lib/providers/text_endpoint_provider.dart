import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_endpoint.dart';
import 'config_provider.dart';

final textServerEndpointsProvider = Provider<List<ServerEndpoint>>((ref) {
  final webDav = ref.watch(enabledServersProvider).map(WebDavEndpoint.new);
  final gotify = ref.watch(gotifyConfigProvider);
  return [
    ...webDav,
    if (gotify.registerAsTextServer) GotifyTextEndpoint(gotify),
  ];
});

final activeTextEndpointProvider = Provider<ServerEndpoint?>((ref) {
  final id = ref.watch(configProvider).valueOrNull?.activeTextServerId;
  final endpoints = ref.watch(textServerEndpointsProvider);
  return endpoints.where((endpoint) => endpoint.id == id).firstOrNull;
});
