import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'game_packet.dart';
import 'game_states.dart';
import 'packet_types.dart';
import 'host.dart';
import 'player.dart';

import 'lobby.dart';
import 'online_player_data.dart';

const debug = true;

class GameServer {
  final int port;
  Map<String, Lobby> rooms = {};
  int id = 0;
  Map<String, OnlinePlayerData> onlinePlayerData = {};
  final Duration heartbeatInterval = Duration(seconds: 5);
  final Duration heartbeatTimeout = Duration(seconds: 15);

  GameServer(this.port);

  Future<void> start() async {
    var context = SecurityContext()
      ..useCertificateChain('./certificate.pem')
      ..usePrivateKey('./private_key.pem', password: "bushido");

    // Cria um servidor seguro usando TLS
    var server = await SecureServerSocket.bind(
      InternetAddress.anyIPv4,
      55656,
      context,
    );

    print(
        'Servidor seguro rodando em ${server.address.address}:${server.port}');
    Timer.periodic(heartbeatInterval, (timer) => _checkHeartbeats());
    await for (var client in server) {
      _handleConnection(client);
    }
  }

  void _handleConnection(SecureSocket socket) {
    print(
        'Nova conexão de ${socket.remoteAddress.address}:${socket.remotePort}');
    socket.listen(
      (List<int> data) {
        final message = utf8.decode(data);
        if (message == "heartbeat\n") {
          _handleHeartBeat(socket);
        } else {
          _handleMessage(socket, message);
        }
      },
      onDone: () {
        _handleDisconnect(socket);
      },
      onError: (error) {
        print('Erro: $error');
      },
    );
  }

  void sendPacketToAllPlayers(GamePacket packet, List<Player> players) {
    for (var player in players) {
      player.socket.write(packet);
    }
  }

  void _handleMessage(socket, message) {
    GamePacket packet = GamePacket.fromString(message);
    final type = packet.type;
    print("PACKET: $packet");
    print("---------------");
    switch (type) {
      case PacketType.createLobby:
        handleCreateLobby(packet, socket);
        break;
      case PacketType.listLobbys:
        handleListLobbys(socket, packet);
        break;
      case PacketType.newPlayer:
        handleNewPlayer(packet, socket);
        break;
      case PacketType.findLobby:
        handleEnterLobby(packet, socket);
        break;
      case PacketType.gameStateChange:
        setGameState(packet);
        break;
      case PacketType.setToGuess:
        handleSetToGuess(packet, socket);
        break;
      case PacketType.passTurn:
        for (var player in rooms[packet.lobbyName]!.playersList) {
          if (player.socket != socket) player.socket.write(packet);
        }
        break;
      case PacketType.chatMessage:
        for (var player in rooms[packet.lobbyName]!.playersList) {
          player.socket.write(packet.toString());
        }
        break;
      case PacketType.restartGame:
        handleRestartGame(packet.lobbyName!);
        for (var player in rooms[packet.lobbyName]!.playersList) {
          player.socket.write(packet.toString());
        }
        break;
      default:
        break;
    }
  }

  void _handleHeartBeat(SecureSocket socket) {
    final clientKey = _getClientKey(socket);
    print(clientKey);
    onlinePlayerData[clientKey]?.lastHeartBeat = DateTime.now();
    print("Recebido heartbeat de $clientKey");
  }

  void _checkHeartbeats() {
    final currentTime = DateTime.now();
    onlinePlayerData.forEach((key, playerData) {
      if (currentTime.difference(playerData.lastHeartBeat) > heartbeatTimeout) {
        print('Cliente $key desconectado devido ao timeout');
        _handleDisconnect(playerData.socket);
      }
    });
  }

  void handleRestartGame(String lobbyName) {
    rooms.update(lobbyName, (lobby) {
      for (var player in lobby.playersList) {
        player.toGuess = null;
        player.image = null;
      }
      lobby.gameState = GameState.waitingPlayers;
      return lobby;
    });
  }

  void retransmitPacket(
      GamePacket packet, Lobby lobby, SecureSocket socketSource) {
    for (int i = 0; i < lobby.playersList.length; i++) {
      if (socketSource != lobby.playersList[i].socket) {
        lobby.playersList[i].socket.write(packet);
      }
    }
  }

  String _getClientKey(SecureSocket socket) {
    return '${socket.remoteAddress.address}:${socket.remotePort}';
  }

  void handleSetToGuess(GamePacket packet, SecureSocket socket) {
    rooms.update(packet.lobbyName!, (lobby) {
      retransmitPacket(packet, lobby, socket);
      final indexPlayer = lobby.playersList
          .indexWhere((player) => player.nick == packet.playerNick);
      lobby.playersList[indexPlayer].setToGuess = packet.toGuess!;
      if (packet.image != null) {
        lobby.playersList[indexPlayer].setImage = packet.image!;
      }
      if (isAllPlayersToGuessSetted(lobby.playersList)) {
        GamePacket sendPacket = GamePacket(
            fromHost: true,
            playerNick: "HOSTSERVER",
            playerIP: InternetAddress("0.0.0.0"),
            type: PacketType.gameStateChange,
            newGameState: GameState.gameStarting);
        sendPacketToAllPlayers(sendPacket, lobby.playersList);
      }
      return lobby;
    });
  }

  void setGameState(GamePacket packet) {
    final lobby = rooms[packet.lobbyName];
    sendPacketToAllPlayers(packet, lobby!.playersList);
    if (packet.newGameState == GameState.waitingPlayerChooseToGuess) {
      setPlayerOrder(packet.playerOrder!, packet.lobbyName!);
    }
  }

  bool isAllPlayersToGuessSetted(players) {
    for (var player in players) {
      if (player.toGuess == null) {
        print("not All players setted to guess");
        return false;
      }
    }
    return true;
  }

  void setPlayerOrder(List<String> playerOrder, String lobbyName) {
    rooms.update(lobbyName, (lobby) {
      for (int i = 0; i < lobby.playersList.length; i++) {
        for (int j = i; j < lobby.playersList.length; j++) {
          if (playerOrder[i] == lobby.playersList[j].nick) {
            var aux = lobby.playersList[i];
            lobby.playersList[i] = lobby.playersList[j];
            lobby.playersList[j] = aux;
          }
        }
      }
      return lobby;
    });
  }

  void handleCreateLobby(GamePacket packet, socket) {
    String response = "";
    if (rooms.containsKey(packet.lobbyName)) {
      response = "ERROR;Nome indisponivel";
      if (debug) print("Erro ao criar lobby:\n $packet");
    } else {
      Lobby lobby = Lobby(rooms.length, packet.lobbyName!, packet.theme!,
          packet.password != null, GameState.waitingPlayers, [],
          password: packet.password);
      rooms.addAll({"${packet.lobbyName}": lobby});
      response = "SUCCESS";
      if (debug) {
        print("Lobby criado:\n");
        showLobbyInformation(lobby);
      }
    }
    print("Enviando resposta $response");
    socket.write(response);
  }

  void handleListLobbys(socket, packet) {
    List<String> lobbys = [];
    String response = "";
    if (packet.lobbyName == null) {
      rooms.forEach((nome, lobby) {
        if (lobby.gameState == GameState.waitingPlayers) {
          lobbys.add(
              "$nome/${lobby.theme}/${lobby.hasPassword}/${lobby.playersList.length}");
        }
      });
      response = "LOBBY_LIST;${jsonEncode(lobbys)}";
    } else {
      final res = rooms[packet.lobbyName];
      if (res != null) {
        lobbys.add(
            "${res.name}/${res.theme}/${res.hasPassword}/${res.playersList.length}");
        response = "LOBBY_LIST;${jsonEncode(lobbys)}";
      } else {
        response = "ERROR;lobbyNaoEncontrado";
      }
    }

    socket.write(response);
  }

  void handleNewPlayer(GamePacket packet, socket) {
    final lobby = rooms[packet.lobbyName];
    GamePacket responsePacket = GamePacket(
        fromHost: true,
        playerNick: "HOSTSERVER",
        type: PacketType.sendPlayersAlreadyInLobby,
        playerIP: InternetAddress.anyIPv4);
    if (lobby != null) {
      responsePacket.playersAlreadyInLobby = List<Map<String, String>>.generate(
          lobby.playersList.length,
          (index) => {"nick": lobby.playersList[index].nick, "ip": "0.0.0.0"});
      lobby.playersList.add(packet.fromHost
          ? Host(packet.playerNick, socket)
          : Player(packet.playerNick, socket));
      onlinePlayerData.addAll({
        "${socket.remoteAddress.address}:${socket.remotePort}":
            OnlinePlayerData(
                lobby.name, packet.fromHost, DateTime.now(), socket)
      });
      responsePacket.response = "SUCCESS";
      sendPacketToAllPlayers(packet, lobby.playersList);
    } else {
      responsePacket.response = "ERROR;Erro ao se conectar";
    }
    socket.write(responsePacket.toString());
  }

  void showLobbyInformation(Lobby lobby) {
    print("#######################");
    print("Nome: ${lobby.name}\n");
    print("------------------------");
    print("Players: ");
    for (var player in lobby.playersList) {
      print("Nome: ${player.nick}\n");
    }
    print("#######################");
  }

  void sendCallbackPlayerDisconnected(
      Lobby lobby, String playerNick, bool playerHost) {
    GamePacket packet;
    print("sending callback for other players");
    if (playerHost) {
      packet = GamePacket(
          fromHost: true,
          playerNick: playerNick,
          type: PacketType.quitGame,
          playerIP: InternetAddress('0.0.0.0'));
    } else {
      packet = GamePacket(
          fromHost: true,
          playerNick: playerNick,
          type: PacketType.playerDisconnect,
          playerIP: InternetAddress('0.0.0.0'));
    }
    sendPacketToAllPlayers(packet, lobby.playersList);
    print("callback sended");
  }

  void closeLobby(String lobbyName, SecureSocket socket) {
    final lobby = rooms[lobbyName];
    if (lobby != null) {
      rooms.removeWhere((key, value) => key == lobbyName);
    }
    socket.close();
  }

  bool equalSockets(socket1, socket2) {
    return socket1.remoteAddress.address == socket2.remoteAddress.address &&
        socket1.remotePort == socket2.remotePort;
  }

  void _handleDisconnect(SecureSocket socket) {
    print('Online players: $onlinePlayerData');

    String clientKey = _getClientKey(socket);
    OnlinePlayerData? playerData = onlinePlayerData[clientKey];
    bool playerHost = false;
    Lobby theLobby;

    if (playerData != null) {
      if (!rooms.containsKey(playerData.lobbyName)) {
        socket.close();
        return;
      }
      String playerNick = "";
      theLobby = rooms.update(playerData.lobbyName, (lobby) {
        lobby.playersList.removeWhere((player) {
          print(
              "${player.nick}\nplayer Address: ${player.socket.remoteAddress.address}\nsocket Address: ${socket.remoteAddress.address}\nsocket port: ${socket.remotePort}\nplayer port: ${player.socket.remotePort}\n");
          final found = socket == player.socket;
          if (found) {
            playerNick = player.nick;
            playerHost = player.isHost;
          }
          print("player $playerNick removido");

          return found;
        });
        return lobby;
      });

      sendCallbackPlayerDisconnected(theLobby, playerNick, playerHost);
      onlinePlayerData.removeWhere((key, value) => key == clientKey);

      if (theLobby.playersList.isEmpty) {
        print("sala vazia");
        closeLobby(theLobby.name, socket);
        return;
      }
    }
    print("Destruindo socket");
    socket.close();
    if (debug) print("DISCONNECTED");
  }

  bool nickAlreadyChoosen(List<Player> list, String nick) {
    for (var player in list) {
      if (player.nick == nick) {
        return true;
      }
    }
    return false;
  }

  void handleEnterLobby(GamePacket packet, socket) {
    final lobby = rooms[packet.lobbyName];
    GamePacket responsePacket = GamePacket(
        fromHost: true,
        playerNick: "HOSTSERVER",
        type: PacketType.packetResponse,
        playerIP: InternetAddress.anyIPv4);
    if (lobby != null) {
      if (nickAlreadyChoosen(lobby.playersList, packet.playerNick)) {
        responsePacket.response = "ERROR;Nick ja escolhido";
      } else {
        if (lobby.hasPassword) {
          if (packet.password != null && packet.password == lobby.password) {
            responsePacket.response = "SUCCESS";
          } else {
            responsePacket.response = "ERROR;Senha invalida";
          }
        } else {
          responsePacket.response = "SUCCESS";
        }
      }
    } else {
      responsePacket.response = "ERROR;Lobby nao encontrado";
    }
    socket.write(responsePacket.toString());
  }
}
