using System;
using System.Globalization;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

public class Tower : MonoBehaviour
{
    [SerializeField] private Slider towerHpSlider;
    [SerializeField] private TextMeshProUGUI hpText;

    private float _towerHp;
    private float _startTowerHp;
    private bool _gameEnded;
    private float _lastTowerShotTime;
    
    private const float TOWER_SHOT_COOLDOWN = 0.3f;

    public Action<float> TowerShotAction { get; set; }

    public void Initialize(float startTowerHp)
    {
        _startTowerHp = startTowerHp;

        UpdateTowerHp(_startTowerHp);
    }

    public void OnTowerShot(float dmgMultiplier)
    {
        if (_gameEnded)
            return;
        
        if (Time.time - _lastTowerShotTime < TOWER_SHOT_COOLDOWN)
            return;
        
        _lastTowerShotTime = Time.time;
        
        var newHp = _towerHp - dmgMultiplier;
        UpdateTowerHp(newHp);
    }

    public void UpdateTowerHp(float towerHp)
    {
        _towerHp = towerHp;
        _towerHp = Mathf.Clamp(_towerHp, 0, _startTowerHp);

        towerHpSlider.value = _towerHp / 100;
        hpText.text = _towerHp.ToString(CultureInfo.InvariantCulture);

        if (_towerHp <= 0)
            _gameEnded = true;
        
        Debug.LogError("tower action call");
        TowerShotAction?.Invoke(_towerHp);
    }
}