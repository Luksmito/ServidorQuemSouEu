
import 'dart:io';

import 'package:quem_sou_eu/data/game_data/game_packet.dart';
import 'package:quem_sou_eu/data/game_data/game_states.dart';
import 'package:quem_sou_eu/data/game_data/packet_types.dart';

class Player {
  final String nick;
  final InternetAddress myIP;
  String? image;
  String? toGuess; 


  Player(this.nick, this.myIP);

  set setImage(String image) => this.image = image;
  set setToGuess(String toGuess) => this.toGuess = toGuess;
  String? get getImage => image;
  String? get getToGuess => toGuess;
  bool get isHost => false;

  GamePacket createNewPlayerPacket() {
    GamePacket packet = GamePacket(
      fromHost: isHost, 
      newPlayerNick: nick,
      playerNick: nick, 
      playerIP: myIP,
      type: PacketType.newPlayer
    );
    return packet;
  }

  GamePacket createChangeStatePacket(GameState newGameState){
    return GamePacket(
      fromHost: isHost, 
      playerNick: nick, 
      playerIP: myIP,
      type: PacketType.gameStateChange,
      newGameState: newGameState
    );
  }

  GamePacket createSetToGuessPacket(Map<String,String> toGuess) {
    return GamePacket(
      fromHost: isHost,
      playerNick: toGuess["nick"]!,
      playerIP: myIP,
      type: PacketType.setToGuess,
      toGuess: toGuess["toGuess"],
      image: toGuess["image"]
    );
  }

  GamePacket createPassTurnPacket() {
    return GamePacket(
      fromHost: isHost,
      playerNick: nick,
      playerIP: myIP,
      type: PacketType.passTurn,
    );
  }

  GamePacket createQuitGamePacket() {
    return GamePacket(
      fromHost: isHost,
      playerNick: nick,
      playerIP: myIP,
      type: PacketType.quitGame,
    );
  }

  GamePacket createRestartGamePacket() {
    return GamePacket(
      fromHost: isHost,
      playerNick: nick,
      playerIP: myIP,
      type: PacketType.restartGame,
    );
  }

  GamePacket createMessagePacket(String message) {
    return GamePacket(
      fromHost: isHost,
      playerNick: nick,
      playerIP: myIP,
      type: PacketType.chatMessage,
      response: message 
    );
  }

}