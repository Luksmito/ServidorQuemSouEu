import 'dart:io';

import 'package:quem_sou_eu/data/game_data/game_states.dart';
import 'package:quem_sou_eu/data/game_data/packet_types.dart';
import 'dart:convert';

class GamePacket {
  final String playerNick;
  final bool fromHost;
  final PacketType type;
  final InternetAddress playerIP;

  List<String>? playerOrder;
  GameState? newGameState;
  List<Map<String,dynamic>>? playersAlreadyInLobby;
  String? toGuess;
  String? image;
  String? response;
  String? newPlayerNick;
  String? lobbyName;
  String? theme;
  String? password;

  GamePacket(
      {required this.fromHost,
      required this.playerNick,
      required this.type,
      required this.playerIP,
      this.newGameState,
      this.playersAlreadyInLobby,
      this.playerOrder,
      this.toGuess,
      this.image,
      this.response,
      this.newPlayerNick,
      this.lobbyName,
      this.theme,
      this.password
      });

  factory GamePacket.fromMap(Map<String, dynamic> packet) {
    
    return GamePacket(
        fromHost: packet["fromHost"],
        playerNick: packet["playerNick"],
        playerIP: InternetAddress(packet["playerIP"]),
        newPlayerNick: packet["newPlayerNick"],
        type: packet["type"] is PacketType
            ? packet["type"]
            : packetTypeFromString(packet["type"]),
        playersAlreadyInLobby: packet["playersAlreadyInLobby"] != null
            ? List<Map<String,String>>.generate(packet["playersAlreadyInLobby"].length,
                (index) => {
                  "nick": packet["playersAlreadyInLobby"][index]["nick"].toString(),
                  "ip": packet["playersAlreadyInLobby"][index]["ip"].toString()
                  })
            : null,
        newGameState: packet["newGameState"] is GameState
            ? packet["newGameState"]
            : gameStateFromString(packet["newGameState"]),
        playerOrder: packet["playerOrder"] != null
            ? List<String>.generate(packet["playerOrder"].length,
                (index) => packet["playerOrder"][index])
            : null,
        toGuess: packet["toGuess"],
        image: packet["image"],
        response: packet["response"],
        lobbyName: packet["lobbyName"],
        theme: packet["theme"],
        password: packet["password"]
      );
  }

  factory GamePacket.fromString(String packet) {
    Map<String, dynamic> map = json.decode(packet);
    return GamePacket.fromMap(map);
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = {
      'playerNick': playerNick,
      'fromHost': fromHost,
      'playerIP': playerIP.address,
      'type': type.toString(),
    };

    if (newGameState != null) data['newGameState'] = newGameState.toString();
    if (playersAlreadyInLobby != null) data['playersAlreadyInLobby'] = playersAlreadyInLobby;
    if (playerOrder != null) data['playerOrder'] = playerOrder;
    if (toGuess != null) data['toGuess'] = toGuess;
    if (image != null) data['image'] = image;
    if (response != null) data['response'] = response;
    if (newPlayerNick != null) data['newPlayerNick'] = newPlayerNick;
    if (lobbyName != null) data['lobbyName'] = lobbyName;
    if (theme != null) data['theme'] = theme;
    if (password != null) data['password'] = password;
    return data;
  }

  @override
  String toString() {
    return json.encode(toJson());
  }
}
