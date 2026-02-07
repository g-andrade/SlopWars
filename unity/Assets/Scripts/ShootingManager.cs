using UnityEngine;

public class ShootingManager : MonoBehaviour
{
    private GameObject _objectToShoot;
    private GameObject _shield;
    
    public bool ShootingOn { get; set; }

    private PlayerManager _playerManager;
    private Transform _shootParent;
    private float _shootDmg;
    
    public void Init(PlayerManager playerManager, Transform shootParent, float shootDmg, GameObject objectToShoot, GameObject shield)
    {
        _objectToShoot = objectToShoot;
        _shield = shield;
        _playerManager = playerManager;
        _shootParent = shootParent;
        _shootDmg = shootDmg;
        
        _objectToShoot.AddComponent<ShotObject>();
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
        if (_objectToShoot == null || _shootParent == null)
        {
            Debug.LogError("Shooting error not found ref");
            return;
        }
        
        _playerManager?.SendShootMessage(_shootDmg); // this is null for the opponent shooting manager

        var instance = Instantiate(_objectToShoot, _shootParent, false);

        var shieldInstance = Instantiate(_shield, instance.transform);

        shieldInstance.SetActive(false);

        instance.SetActive(true);

        var transform1 = instance.transform;
        transform1.localPosition = Vector3.zero;
        transform1.localRotation = _objectToShoot.transform.localRotation;

        transform1.SetParent(transform);

        instance.GetComponent<ShotObject>().OnShoot(_shootDmg);
    }
}