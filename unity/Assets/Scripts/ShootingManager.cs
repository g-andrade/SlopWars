using System.Collections.Generic;
using UnityEngine;

public class ShootingManager : MonoBehaviour
{
    [SerializeField] private ShotObject shotObjectPrefab;

    private readonly List<ShotObject> _shots = new();
    
    public bool ShootingOn { get; set; }

    private PlayerManager _playerManager;
    private Transform _shootParent;
    private float _shootDmg;
    
    public void Init(PlayerManager playerManager, Transform shootParent, float shootDmg)
    {
        _playerManager = playerManager;
        _shootParent = shootParent;
        _shootDmg = shootDmg;
    }
    
    private void Update()
    {
        if (!ShootingOn)
            return;
        
        HandleShootInput();
    }

    private void HandleShootInput()
    {
        if (Input.GetMouseButtonDown(0))
        {
            OnShoot();
        }
    }

    public void OnShoot()
    {
        if (shotObjectPrefab == null || _shootParent == null)
        {
            Debug.LogError("Shooting error not found ref");
            return;
        }

        _playerManager?.SendShootMessage(_shootDmg); // this is null for the opponent shooting manager

        var instance = Instantiate(shotObjectPrefab, _shootParent, false);

        var transform1 = instance.transform;
        transform1.localPosition = Vector3.zero;
        transform1.localRotation = shotObjectPrefab.transform.localRotation;

        transform1.SetParent(transform);

        _shots.Add(instance);
        instance.OnShoot(_shootDmg);
    }
}