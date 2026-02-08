using System;
using Newtonsoft.Json;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

public class MainScreen : MonoBehaviour
{
    [SerializeField] private Button connectButton, sendButton;
    [SerializeField] private TMP_InputField promptInput;
    [SerializeField] private GameObject promptTitle;

    private WebSocketsClient _webSocketsClient;
    
    public void Init(WebSocketsClient webSocketsClient)
    {
        _webSocketsClient = webSocketsClient;

        _webSocketsClient.OnMessageReceived += OnMessageReceived;
    }

    private void OnMessageReceived(string json)
    {
        var message = JsonConvert.DeserializeObject<MessageObject>(json);
        
        switch (message.Type)
        {
            case "queued":
                connectButton.GetComponentInChildren<TextMeshProUGUI>().text = "IN QUEUE";
                break;
            case "matched":
                connectButton.GetComponentInChildren<TextMeshProUGUI>().text = "OPPONENT FOUND";
                promptTitle.SetActive(true);
                promptInput.gameObject.SetActive(true);
                break;
            case "both_prompts_in":
                connectButton.GetComponentInChildren<TextMeshProUGUI>().text = "ANALYZING...";
                break;
        }
    }

    private void OnEnable()
    {
        promptTitle.SetActive(false);
        promptInput.gameObject.SetActive(false);
        connectButton.onClick.AddListener(OnConnectButton);
        promptInput.onSubmit.AddListener(OnSubmitPrompt);
        sendButton.onClick.AddListener(OnSend);
    }

    private void OnSend()
    {
        OnSubmitPrompt(promptInput.text);
    }

    private void OnDisable()
    {
        connectButton.onClick.RemoveListener(OnConnectButton);
        promptInput.onSubmit.RemoveListener(OnSubmitPrompt);
        sendButton.onClick.RemoveListener(OnSend);
        
        _webSocketsClient.OnMessageReceived -= OnMessageReceived;
    }

    private async void OnSubmitPrompt(string prompt)
    {
        var promptMessage = new MessageObject
        {
            Type = "submit_prompt",
            Prompt = prompt
        };

        promptInput.interactable = false;
        connectButton.GetComponentInChildren<TextMeshProUGUI>().text = "PREPARING BATTLE...";
        
        await _webSocketsClient.SendAsync(promptMessage);
    }

    private async void OnConnectButton()
    {
        connectButton.interactable = false;

        await _webSocketsClient.ConnectAsync();

        var queueMessage = new MessageObject
        {
            Type = "join_queue"
        };
        await _webSocketsClient.SendAsync(queueMessage);
    }
}