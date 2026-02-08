using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEngine;

public class PlayerManager
{
    private readonly int _playerId;
    private readonly Transform _playerTransform, _playerCanon;
    private readonly WebSocketsClient _wsClient;
    private readonly Tower _opponentTower;

    public PlayerManager(int playerId, WebSocketsClient wsClient, Transform playerTransform, Tower opponentTower, Transform playerCanon)
    {
        _playerId = playerId;
        _playerTransform = playerTransform;
        _wsClient = wsClient;
        _playerCanon = playerCanon;
        _opponentTower = opponentTower;
        
        _ = SendPositionLoop();

        TowerUpdateLoop();
    }

    private async void TowerUpdateLoop()
    {
        while (true)
        {
            await Task.Delay(1000);
            SendTowerHpUpdate(_opponentTower.TowerHp);
        }
    }
    
    public void SendShootMessage(float dmg)
    {
        var shootMsg = new MessageObject
        {
            Type = "shoot",
            Power = dmg
        };

        _wsClient.SendAsync(shootMsg);
    }

    private void SendTowerHpUpdate(float towerHp)
    {
        var towerMsg = new MessageObject
        {
            Type = "tower_hp",
            TowerHp = towerHp
        };
        
        Debug.LogError($"sending {JsonConvert.SerializeObject(towerMsg)}");

        _wsClient.SendAsync(towerMsg);
    }

    private async Task SendPositionLoop()
    {
        while (true)
        {
            await Task.Delay(200);
            SendPositionMessage();
        }
    }

    private void SendPositionMessage()
    {
        var positionMsg = new MessageObject
        {
            Type = "player_update",
            Position = _playerTransform.position.ToNumerics(),
            Rotation1 = _playerTransform.rotation.ToNumerics(),
            Rotation2 = _playerCanon.rotation.ToNumerics()
        };
        
        _wsClient.SendAsync(positionMsg);
    }
}