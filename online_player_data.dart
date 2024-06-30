import 'dart:io';

class OnlinePlayerData {
  final String lobbyName;
  final bool isHost;
  DateTime lastHeartBeat;
  SecureSocket socket;
  
  OnlinePlayerData(this.lobbyName, this.isHost, this.lastHeartBeat, this.socket);

  set setLastHeartBeat(DateTime _lastHeartBeat) {
    lastHeartBeat = lastHeartBeat;
  }
}