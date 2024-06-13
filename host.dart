
import 'player.dart';

class Host extends Player {
 
  Host(super.nick, super.myIP, super.port);


  List<String> ips = [];

  @override
  bool get isHost => true;

  List<String> get getIps => ips;

  set addIp(String ip) => ips.add(ip);

  
}
