import 'dart:io';
import 'dart:async';
import 'dart:convert';

class GameClient {
  final String serverIp;
  final int serverPort;
  SecureSocket? _socket;
  final Duration heartbeatInterval = Duration(seconds: 5);
  bool _connected = false;

  GameClient(this.serverIp, this.serverPort);

  Future<void> connect() async {
    
    while (!_connected) {
      try {
        _socket = await SecureSocket.connect(serverIp, serverPort, onBadCertificate: (certificate)=>true);
        _connected = true;
        print('Conectado ao servidor');
        Timer.periodic(heartbeatInterval, (timer) => _sendHeartbeat());
        _socket!.listen(
          (data) {
            print('Servidor: ${utf8.decode(data)}');
          },
          onDone: () {
            _connected = false;
            print('Desconectado do servidor');
            _reconnect();
          },
          onError: (error) {
            _connected = false;
            print('Erro: $error');
            _reconnect();
          },
        );
      } catch (e) {
        print('Falha na conexão: $e. Tentando novamente em 5 segundos...');
        await Future.delayed(Duration(seconds: 5));
      }
    }
  }

  void _sendHeartbeat() {
    if (_connected && _socket != null) {
      _socket!.write('heartbeat\n');
    }
  }

  void _reconnect() {
    _connected = false;
    _socket?.destroy();
    connect();
  }

  void close() {
    _connected = false;
    _socket?.close();
    _socket?.destroy();
  }
}

void main() async {
  final client = GameClient('127.0.0.1', 55656);
  await client.connect();
}
