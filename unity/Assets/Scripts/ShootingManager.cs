using System.Collections.Generic;
using UnityEngine;

public class ShootingManager : MonoBehaviour
{
    [SerializeField] private ShotObject shotObjectPrefab;
    [SerializeField] private Transform shotParent;

    private readonly List<ShotObject> _shots = new();
    
    private void Update()
    {
        HandleShootInput();
    }

    private void HandleShootInput()
    {
        if (Input.GetMouseButtonDown(0))
        {
            OnShoot();
        }
    }

    private void OnShoot()
    {
        if (shotObjectPrefab == null || shotParent == null)
        {
            Debug.LogError("Shooting error not found ref");
            return;
        }

        var instance = Instantiate(shotObjectPrefab, shotParent, false);

        var transform1 = instance.transform;
        transform1.localPosition = Vector3.zero;
        transform1.localRotation = shotObjectPrefab.transform.localRotation;

        transform1.SetParent(transform);

        _shots.Add(instance);
        instance.OnShoot();
    }
}