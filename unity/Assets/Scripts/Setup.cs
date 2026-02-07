using System;
using Newtonsoft.Json;
using UnityEngine;

public class Setup : MonoBehaviour
{
    [SerializeField] private string socketUrl;
    [SerializeField] private MovementManager movementManager;
    [SerializeField] private ShootingManager playerShootingManager, opponentShootingManager;
    [SerializeField] private Transform player, opponent, a1Spawn, a2Spawn, playerShootParent, opponentShootParent;
    [SerializeField] private Tower a1tower, a2tower;
    [SerializeField] private MainScreen mainScreen;
    [SerializeField] private EndGameScreen endGameScreen;
    [SerializeField] private Transform playerCannon, opponentCanon;

    private WebSocketsClient _wsClient;
    private PlayerManager _playerManager;
    private OpponentManager _opponentManager;
    private Action<string> _onMessageReceived;
    private Build _playerBuild;
    private Build _opponentBuild;
    private int _playerId;
            
    private void Start()
    {
        _wsClient = new WebSocketsClient(socketUrl);

        _wsClient.OnMessageReceived += OnMessageReceived;
        
        mainScreen.Init(_wsClient);
    }

    private void OnMessageReceived(string json)
    {
        var message = JsonConvert.DeserializeObject<MessageObject>(json);

        switch (message.Type)
        {
            case "matched":
                _playerId = message.PlayerNumber;
                break;
            case "builds_ready":
                _playerBuild = message.PlayerBuild;
                _opponentBuild = message.OpponentBuild;
                OnStartGame();
                break;
            case "game_over":
                endGameScreen.gameObject.SetActive(true);
                endGameScreen.Init(message.Winner == _playerId ? "YOU WIN" : "YOU LOSE");
                break;
        }
    }

    private void OnStartGame()
    {
        mainScreen.gameObject.SetActive(false);
        
        var playerIsA1 = _playerId == 1;
        
        player.position = playerIsA1 ? a1Spawn.position : a2Spawn.position;
        player.rotation = playerIsA1 ? a1Spawn.rotation : a2Spawn.rotation;

        opponent.position = playerIsA1 ? a2Spawn.position : a1Spawn.position;
        opponent.rotation = playerIsA1 ? a2Spawn.rotation : a1Spawn.rotation;
        
        a1tower.Initialize(playerIsA1 ? _playerBuild.tower_hp : _opponentBuild.tower_hp);
        a2tower.Initialize(playerIsA1 ? _opponentBuild.tower_hp : _playerBuild.tower_hp);

        _playerManager = new PlayerManager(_playerId, _wsClient, player, playerIsA1 ? a2tower : a1tower, playerCannon);
        _opponentManager = new OpponentManager(_playerId == 1 ? 2 : 1, _wsClient, opponent, opponentShootingManager,
            playerIsA1 ? a1tower : a2tower, opponentCanon);

        playerShootingManager.Init(_playerManager, playerShootParent, _playerBuild.bomb_damage);
        opponentShootingManager.Init(null, opponentShootParent, _opponentBuild.bomb_damage);

        movementManager.MovementOn = true;
        playerShootingManager.ShootingOn = true;
        opponentShootingManager.ShootingOn = false;

        movementManager.StartGame();
    }

    private void Update()
    {
        _opponentManager?.RunOnUpdate?.Invoke();
    }
}