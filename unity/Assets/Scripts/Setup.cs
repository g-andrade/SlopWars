using System;
using System.Collections.Generic;
using System.Threading.Tasks;
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
    [SerializeField] private RuntimeAssetFactory runtimeAssetFactory;
    [SerializeField] private GameObject shieldVolume, projectileVolume;

    private WebSocketsClient _wsClient;
    private PlayerManager _playerManager;
    private OpponentManager _opponentManager;
    private Action<string> _onMessageReceived;
    private Build _playerBuild;
    private Build _opponentBuild;
    private int _playerId;
    private bool _building;

    private readonly Dictionary<string, string> _receivedAssets = new();

    private GameObject _playerShootObject, _playerShield;
    private GameObject _opponentShootObject, _opponentShield;
            
    private void Start()
    {
        _wsClient = new WebSocketsClient(socketUrl);

        _wsClient.OnMessageReceived += OnMessageReceived;
        
        mainScreen.Init(_wsClient);

        // todo move
        var towerUrl = "https://file.hyper3d.com/4dbe121b-7806-4e5c-aa7e-e264241e7066/pack/glb/base_basic_pbr.glb?response-cache-control=private&response-content-type=model%2Fgltf-binary&response-content-disposition=attachment%3B%20filename%3D%22base_basic_pbr.glb%22&X-Tos-Algorithm=TOS4-HMAC-SHA256&X-Tos-Content-Sha256=UNSIGNED-PAYLOAD&X-Tos-Credential=AKLTYzE0MDRlNzUyNWMzNGE5N2JlZTQ5ZGRkZWQ2NWY5ZTA%2F20260207%2Ffile.hyper3d.com%2Ftos%2Frequest&X-Tos-Date=20260207T192210Z&X-Tos-Expires=604800&X-Tos-SignedHeaders=host&X-Tos-Signature=71ce937cffe052e1eb1e55db177fbd3ed2c474b7dc0a55adbe04a5f00c21743c";
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
                OnBuildsReady();
                break;
            case "game_over":
                endGameScreen.gameObject.SetActive(true);
                endGameScreen.Init(message.Winner == _playerId ? "YOU WIN" : "YOU LOSE");
                break;
            case "asset_ready":
                var key = $"{message.Name}{message.PlayerNumber}";
                _receivedAssets.Add(key, message.Url);
                break;
            case "playing":
                OnPlay();
                break;
        }
    }

    private async void OnPlay()
    {
        var playerIsA1 = _playerId == 1;
        
        await Task.Yield();
        while (_building) 
            await Task.Yield();
        
        _playerManager = new PlayerManager(_playerId, _wsClient, player, playerIsA1 ? a2tower : a1tower, playerCannon);
        _opponentManager = new OpponentManager(_playerId == 1 ? 2 : 1, _wsClient, opponent, opponentShootingManager,
            playerIsA1 ? a1tower : a2tower, opponentCanon);

        playerShootingManager.Init(_playerManager, playerShootParent, _playerBuild.bomb_damage, _playerShootObject, _playerShield);
        opponentShootingManager.Init(null, opponentShootParent, _opponentBuild.bomb_damage, _opponentShootObject, _opponentShield);

        movementManager.MovementOn = true;
        playerShootingManager.ShootingOn = true;
        opponentShootingManager.ShootingOn = false;

        movementManager.StartGame();
    }

    private async void OnBuildsReady()
    {
        _building = true;
        
        mainScreen.gameObject.SetActive(false);
        
        var playerIsA1 = _playerId == 1;
        
        player.position = playerIsA1 ? a1Spawn.position : a2Spawn.position;
        player.rotation = playerIsA1 ? a1Spawn.rotation : a2Spawn.rotation;

        opponent.position = playerIsA1 ? a2Spawn.position : a1Spawn.position;
        opponent.rotation = playerIsA1 ? a2Spawn.rotation : a1Spawn.rotation;
        
        a1tower.Initialize(playerIsA1 ? _playerBuild.tower_hp : _opponentBuild.tower_hp);
        a2tower.Initialize(playerIsA1 ? _opponentBuild.tower_hp : _playerBuild.tower_hp);

        var tower1Task = ReceivedAssetReady("tower", 1);
        var tower2Task = ReceivedAssetReady("tower", 2);
        var playerBombTask = ReceivedAssetReady("bomb", 1);
        var playerShieldTask = ReceivedAssetReady("shield", 1);
        var opponentBombTask = ReceivedAssetReady("bomb", 2);
        var opponentShieldTask = ReceivedAssetReady("shield", 2);

        await Task.WhenAll(tower1Task, tower2Task, playerBombTask, playerShieldTask, opponentBombTask, opponentShieldTask);

        OnTower1Ready(tower1Task.Result);
        OnTower2Ready(tower2Task.Result);
        OnPlayerBombReady(playerBombTask.Result);
        OnPlayerShieldReady(playerShieldTask.Result);
        OnOpponentBombReady(opponentBombTask.Result);
        OnOpponentShieldReady(opponentShieldTask.Result);

        _building = false;
    }

    private void Update()
    {
        _opponentManager?.RunOnUpdate?.Invoke();
    }

    private async Task<GameObject> ReceivedAssetReady(string assetId, int playerId)
    {
        while (!_receivedAssets.TryGetValue($"{assetId}{playerId}", out _))
            await Task.Yield();

        var asyncObject = await runtimeAssetFactory.CreateObjectAsync($"{assetId}{playerId}", _receivedAssets);

        return asyncObject;
    }

    private void OnPlayerBombReady(GameObject playerBomb)
    {
        playerBomb.layer = LayerMask.NameToLayer("Projectile");
        playerBomb.transform.SetParent(runtimeAssetFactory.transform);
        playerBomb.FitToPlaceholder(projectileVolume);
        playerBomb.AddOrUpdateCollider();

        playerBomb.SetActive(false);

        if (_playerId == 1)
            _playerShootObject = playerBomb;
        else
            _opponentShootObject = playerBomb;
    }

    private void OnOpponentBombReady(GameObject opponentBomb)
    {
        opponentBomb.layer = LayerMask.NameToLayer("Projectile");
        opponentBomb.transform.SetParent(runtimeAssetFactory.transform);
        opponentBomb.FitToPlaceholder(projectileVolume);
        opponentBomb.AddOrUpdateCollider();

        opponentBomb.SetActive(false);

        if (_playerId == 1)
            _opponentShootObject = opponentBomb;
        else
            _playerShootObject = opponentBomb;
    }

    private void OnPlayerShieldReady(GameObject playerShield)
    {
        playerShield.layer = LayerMask.NameToLayer("Shield");
        playerShield.transform.SetParent(runtimeAssetFactory.transform);
        playerShield.FitToPlaceholder(shieldVolume);
        playerShield.AddOrUpdateCollider();

        playerShield.SetActive(false);

        if (_playerId == 1)
            _playerShield = playerShield;
        else
            _opponentShield = playerShield;
    }

    private void OnOpponentShieldReady(GameObject opponentShield)
    {
        opponentShield.layer = LayerMask.NameToLayer("Shield");
        opponentShield.transform.SetParent(runtimeAssetFactory.transform);
        opponentShield.FitToPlaceholder(shieldVolume);
        opponentShield.AddOrUpdateCollider();

        opponentShield.SetActive(false);

        if (_playerId == 1)
            _opponentShield = opponentShield;
        else
            _playerShield = opponentShield;
    }
    
    private void OnTower1Ready(GameObject tower)
    {
        tower.transform.localRotation = a1tower.transform.localRotation;
        tower.transform.SetParent(runtimeAssetFactory.transform);
            
        tower.FitToPlaceholder(a1tower.gameObject);
        
        tower.transform.localPosition = a1tower.transform.localPosition;
        tower.layer = LayerMask.NameToLayer("Tower");
        foreach (var t in tower.GetComponentsInChildren<Transform>(true))
            t.gameObject.layer = LayerMask.NameToLayer("Tower");
        tower.AddOrUpdateCollider();
    }
    
    private void OnTower2Ready(GameObject tower)
    {
        tower.transform.localRotation = a2tower.transform.localRotation;
        tower.transform.SetParent(runtimeAssetFactory.transform);
            
        tower.FitToPlaceholder(a2tower.gameObject);
        
        tower.transform.localPosition = a2tower.transform.localPosition;
        tower.layer = LayerMask.NameToLayer("Tower");
        foreach (var t in tower.GetComponentsInChildren<Transform>(true))
            t.gameObject.layer = LayerMask.NameToLayer("Tower");
        tower.AddOrUpdateCollider();
    }
}