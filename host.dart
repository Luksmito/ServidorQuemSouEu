
import 'player.dart';

class Host extends Player {
 
  Host(super.nick, super.socket);

  @override
  bool get isHost => true;
}
