enum GameState {
  waitingPlayers,
  waitingHostSelectOrder,
  waitingPlayerChooseToGuess,
  gameStarting,
  iChoosedToGuess
}

GameState? gameStateFromString(String? value) {
  switch (value) {
    case 'GameState.waitingPlayers':
      return GameState.waitingPlayers;
    case 'GameState.waitingHostSelectOrder':
      return GameState.waitingHostSelectOrder;
    case 'GameState.waitingPlayerChooseToGuess':
      return GameState.waitingPlayerChooseToGuess;
    case 'GameState.gameStarting':
      return GameState.gameStarting;
    default:
      return null;
  }
}