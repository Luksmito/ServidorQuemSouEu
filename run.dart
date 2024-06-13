import "./dedicated_server.dart";

void main() async {
  final server = GameServer(55656);
  server.start();

}