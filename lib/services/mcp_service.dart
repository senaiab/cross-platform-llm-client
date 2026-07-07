import 'dart:convert';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

class McpServer {
  final String name;
  final String url;
  final String? authHeader;
  List<Map<String, dynamic>> cachedTools;
  McpServer({required this.name, required this.url, this.authHeader, this.cachedTools = const []});
}

class McpService extends GetxService {
  final _servers = <String, McpServer>{};
  int _reqId = 1;

  void addServer(String name, String url, {String? authHeader}) =>
      _servers[name] = McpServer(name: name, url: url, authHeader: authHeader);

  void removeServer(String name) => _servers.remove(name);

  List<String> listServers() => _servers.keys.toList();

  Future<Map<String, dynamic>> _rpc(McpServer srv, String method, [Map<String, dynamic>? params]) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (srv.authHeader != null) 'Authorization': srv.authHeader!,
    };
    final body = jsonEncode({'jsonrpc': '2.0', 'id': _reqId++, 'method': method, if (params != null) 'params': params});
    final resp = await http.post(Uri.parse(srv.url), headers: headers, body: body)
        .timeout(const Duration(seconds: 30));
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    if (decoded['error'] != null) {
      final e = decoded['error'] as Map;
      throw Exception('MCP ${e['code']}: ${e['message']}');
    }
    return (decoded['result'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> initialize(String name) async {
    final srv = _servers[name];
    if (srv == null) return {'error': 'server_not_found'};
    final r = await _rpc(srv, 'initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': {},
      'clientInfo': {'name': 'PrivateLM', 'version': '1.0.5'},
    });
    return {'ok': true, 'serverInfo': r['serverInfo'], 'capabilities': r['capabilities']};
  }

  Future<List<Map<String, dynamic>>> listTools(String name) async {
    final srv = _servers[name];
    if (srv == null) return [];
    final r = await _rpc(srv, 'tools/list');
    final tools = (r['tools'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    srv.cachedTools = tools;
    return tools;
  }

  Future<Map<String, dynamic>> callTool(String serverName, String toolName, Map<String, dynamic> arguments) async {
    final srv = _servers[serverName];
    if (srv == null) return {'error': 'server_not_found'};
    return _rpc(srv, 'tools/call', {'name': toolName, 'arguments': arguments});
  }
}
