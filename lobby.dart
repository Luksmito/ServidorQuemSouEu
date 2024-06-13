import 'dart:io';

import 'game_states.dart';
import 'player.dart';

class Lobby {
  final int id;
  final String name;
  final String theme;
  final bool hasPassword;
  GameState gameState;
  List<Socket> playersConnection;
  List<Player> playersList;
  String? password;
  
  Lobby(this.id, this.name, this.theme, this.hasPassword, this.gameState, this.playersConnection, this.playersList, {this.password}) {
    
  }
}