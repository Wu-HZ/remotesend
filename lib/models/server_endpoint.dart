import 'gotify_models.dart';
import 'server_config.dart';

const gotifyTextServerId = 'builtin:gotify:text';

enum ServerKind { webDav, gotify }

class ServerCapabilities {
  const ServerCapabilities({required this.files, required this.history});
  final bool files;
  final bool history;
}

sealed class ServerEndpoint {
  String get id;
  String get name;
  String get emoji;
  ServerKind get kind;
  ServerCapabilities get capabilities;
}

class WebDavEndpoint extends ServerEndpoint {
  WebDavEndpoint(this.server);
  final ServerConfig server;
  @override
  String get id => server.id;
  @override
  String get name => server.name;
  @override
  String get emoji => server.emoji;
  @override
  ServerKind get kind => ServerKind.webDav;
  @override
  ServerCapabilities get capabilities =>
      const ServerCapabilities(files: true, history: true);
}

class GotifyTextEndpoint extends ServerEndpoint {
  GotifyTextEndpoint(this.config);
  final GotifyConfig config;
  @override
  String get id => gotifyTextServerId;
  @override
  String get name => 'Gotify';
  @override
  String get emoji => config.emoji;
  @override
  ServerKind get kind => ServerKind.gotify;
  @override
  ServerCapabilities get capabilities =>
      const ServerCapabilities(files: false, history: false);
}
