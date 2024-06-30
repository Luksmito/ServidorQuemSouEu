import 'dart:io';

import 'game_states.dart';
import 'player.dart';

class Lobby {
  final int id;
  final String name;
  final String theme;
  final bool hasPassword;
  GameState gameState;
  List<Player> playersList;
  String? password;
  
  Lobby(this.id, this.name, this.theme, this.hasPassword, this.gameState, this.playersList, {this.password}) {
    
  }
}