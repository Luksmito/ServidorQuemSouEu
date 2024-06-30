
import 'dart:io';

import 'game_packet.dart';
import 'game_states.dart';
import 'packet_types.dart';

class Player {
  final String nick;
  final SecureSocket socket;
  String? image;
  String? toGuess; 

  Player(this.nick, this.socket);

  set setImage(String image) => this.image = image;
  set setToGuess(String toGuess) => this.toGuess = toGuess;
  String? get getImage => image;
  String? get getToGuess => toGuess;
  bool get isHost => false;

}