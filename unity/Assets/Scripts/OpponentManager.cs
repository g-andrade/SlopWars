using System;
using Newtonsoft.Json;
using UnityEngine;

public class OpponentManager
{
    private readonly int _opponentId;
    private readonly Transform _opponent, _opponentCanon;
    private readonly ShootingManager _opponentShootingManager;
    private readonly Tower _playerTower;
    
    private Vector3 _targetPosition;
    private Quaternion _targetBodyRotation;
    private Quaternion _targetCanonRotation;
    
    public Action RunOnUpdate { get; set; }

    public OpponentManager(int opponentId, WebSocketsClient wsClient, Transform opponent,
        ShootingManager opponentShootingManager, Tower playerTower, Transform opponentCanon)
    {
        _opponentId = opponentId;
        _opponent = opponent;
        _opponentShootingManager = opponentShootingManager;
        _playerTower = playerTower;
        _opponentCanon = opponentCanon;

        wsClient.OnMessageReceived += OnMessageReceived;

        _targetPosition = _opponent.position;
        _targetBodyRotation = _opponent.rotation;
        _targetCanonRotation = _opponentCanon.rotation;

        RunOnUpdate += InterpolateOpponent;
    }

    private void OnMessageReceived(string json)
    {
        var message = JsonConvert.DeserializeObject<MessageObject>(json);

        if (message.PlayerNumber != _opponentId)
            return;
        
        switch (message.Type)
        {
            case "shoot":
                _opponentShootingManager.OnShoot();
                break;
            case "player_update":
                _targetPosition = message.Position.ToUnity();
                _targetBodyRotation = message.Rotation1.ToUnity();
                _targetCanonRotation = message.Rotation2.ToUnity();
                break;
            case "tower_hp":
                Debug.LogError(JsonConvert.SerializeObject(message));
                _playerTower.UpdateTowerHp(message.TowerHp);
                break;
        }
    }
    
    private void InterpolateOpponent()
    {
        // Position
        _opponent.position = Vector3.Lerp(
            _opponent.position,
            _targetPosition,
            10 * Time.deltaTime
        );

        // Body rotation
        _opponent.rotation = Quaternion.Slerp(
            _opponent.rotation,
            _targetBodyRotation,
            12 * Time.deltaTime
        );

        // Canon rotation
        _opponentCanon.rotation = Quaternion.Slerp(
            _opponentCanon.rotation,
            _targetCanonRotation,
            12 * Time.deltaTime
        );
    }
    
}