using TMPro;
using UnityEngine;

public class EndGameScreen : MonoBehaviour
{
    [SerializeField] private TextMeshProUGUI winText;

    public void Init(string winningText)
    {
        winText.text = winningText;
    }
}