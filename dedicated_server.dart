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
  ServerSocket? _server;
  Map<String, Lobby> rooms = {};
  int id = 0;
  Map<String, OnlinePlayerData> onlinePlayerData = {};

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
        _handleMessage(socket, message);
      },
      onDone: () {
        _handleDisconnect(socket);
      },
      onError: (error) {
        print('Erro: $error');
      },
    );
  }

  void sendPacketToAllPlayers(
      GamePacket packet, List<SecureSocket> playersConnection) {
    for (var connection in playersConnection) {
      connection.write(packet);
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
        for (var connection in rooms[packet.lobbyName]!.playersConnection) {
          if (connection != socket) connection.write(packet);
        }
        break;
      case PacketType.chatMessage:
        for (var connection in rooms[packet.lobbyName]!.playersConnection) {
          connection.write(packet.toString());
        }
        break;
      case PacketType.restartGame:
        handleRestartGame(packet.lobbyName!);
        for (var connection in rooms[packet.lobbyName]!.playersConnection) {
          connection.write(packet.toString());
        }
        break;
      default:
        break;
    }
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
    for (int i = 0; i < lobby.playersConnection.length; i++) {
      if (socketSource != lobby.playersConnection[i]) {
        lobby.playersConnection[i].write(packet);
      }
    }
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
        sendPacketToAllPlayers(sendPacket, lobby.playersConnection);
      }
      return lobby;
    });
  }

  void setGameState(GamePacket packet) {
    final lobby = rooms[packet.lobbyName];
    for (int i = 1; i < lobby!.playersConnection.length; i++) {
      lobby.playersConnection[i].write(packet);
    }
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
          packet.password != null, GameState.waitingPlayers, [], [],
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
          ? Host(packet.playerNick, socket.remoteAddress, socket.remotePort)
          : Player(packet.playerNick, socket.remoteAddress, socket.remotePort));
      onlinePlayerData.addAll({
        "${socket.remoteAddress.address}:${socket.remotePort}":
            OnlinePlayerData(lobby.name, packet.fromHost)
      });
      responsePacket.response = "SUCCESS";
      for (var player in lobby.playersList) {
        print("Nicks: ${player.nick}");
      }
      for (var connection in lobby.playersConnection) {
        connection.write(packet);
      }
      lobby.playersConnection.add(socket);
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
      print("Endereço: ${player.myIP}");
    }
    print("------------------------");
    print("Conexoes: \n");
    for (final conexao in lobby.playersConnection) {
      if (conexao != null) {
        print("Endereço: ${conexao.remoteAddress.address}");
      } else {
        print("Nulo");
      }
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
    for (var socket in lobby.playersConnection) {
      socket.write(packet.toString());
    }
    print("callback sended");
  }

  void closeLobby(String lobbyName, SecureSocket socket) {
    final lobby = rooms[lobbyName];
    if (lobby != null) {
      for (var connection in lobby.playersConnection) {
        if (!equalSockets(connection, socket)) {
          connection.destroy();
        }
      }
      rooms.removeWhere((key, value) => key == lobbyName);
    }
  }

  bool equalSockets(socket1, socket2) {
    return socket1.remoteAddress.address == socket2.remoteAddress.address &&
        socket1.remotePort == socket2.remotePort;
  }

  void _handleDisconnect(socket) {
    print('Online players: $onlinePlayerData');
    OnlinePlayerData? playerData = onlinePlayerData[
        "${socket.remoteAddress.address}:${socket.remotePort}"];
    bool playerHost = false;
    Lobby theLobby;
    if (playerData != null) {
      if (!rooms.containsKey(playerData.lobbyName)) {
        socket.destroy();
        return;
      }
      String playerNick = "";
      theLobby = rooms.update(playerData.lobbyName, (lobby) {
        lobby.playersList.removeWhere((player) {
          print(
              "${player.nick}\nplayer Address: ${player.myIP.address}\nsocket Address: ${socket.remoteAddress.address}\nsocket port: ${socket.remotePort}\nplayer port: ${player.port}\n");
          final found = player.myIP.address == socket.remoteAddress.address &&
              socket.remotePort == player.port;
          if (found) {
            playerNick = player.nick;
            playerHost = player.isHost;
          }
          print("player $playerNick removido");

          return found;
        });

        lobby.playersConnection.removeWhere((conexao) =>
            equalSockets(conexao, socket));

        return lobby;
      });
      sendCallbackPlayerDisconnected(theLobby, playerNick, playerHost);
      onlinePlayerData.removeWhere((key, value) =>
          key == "${socket.remoteAddress.address}:${socket.remotePort}");
      if (theLobby.playersList.isEmpty) {
        closeLobby(theLobby.name, socket);
        return;
      }
    }
    socket.destroy();
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
