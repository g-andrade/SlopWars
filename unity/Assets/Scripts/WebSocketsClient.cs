using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using UnityEngine;

public class WebSocketsClient
{
    private readonly string _url;
    
    private ClientWebSocket _ws;
    private CancellationTokenSource _cts;

    public Action<string> OnMessageReceived;

    public WebSocketsClient(string url)
    {
        _url = url;
    }

    public async Task ConnectAsync()
    {
        _ws = new ClientWebSocket();
        _cts = new CancellationTokenSource();

        await _ws.ConnectAsync(new Uri(_url), _cts.Token);
        
        Debug.Log("Connected");

        _ = ReceiveLoop();
    }

    private async Task ReceiveLoop()
    {
        var buffer = new byte[8192];

        try
        {
            while (_ws is { State: WebSocketState.Open } && !_cts.IsCancellationRequested)
            {
                var result = await _ws.ReceiveAsync(new ArraySegment<byte>(buffer), _cts.Token);

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    await CloseAsync();
                    return;
                }
                
                var json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                OnMessage(json);
            }
        }
        catch (Exception ex)
        {
            OnError(ex);
        }
    }

    private void OnMessage(string json)
    {
        Debug.Log($"[WS] {json}");
        
        OnMessageReceived?.Invoke(json);
    }

    private void OnError(Exception ex)
    {
        Debug.LogError($"[WS ERROR] {ex.Message}");
        _ = CloseAsync();
    }

    public async Task SendAsync<T>(T msg)
    {
        if (_ws is not { State: WebSocketState.Open })
            return;

        var json = JsonConvert.SerializeObject(msg);
        var bytes = Encoding.UTF8.GetBytes(json);

        await _ws.SendAsync(
            new ArraySegment<byte>(bytes),
            WebSocketMessageType.Text,
            true,
            _cts.Token
        );
    }

    public async Task CloseAsync()
    {
        try
        {
            _cts?.Cancel();

            if (_ws != null && _ws.State == WebSocketState.Open)
                await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", CancellationToken.None);
        }
        catch { /* intentionally ignored */ }
        finally
        {
            _ws?.Dispose();
            _ws = null;

            _cts?.Dispose();
            _cts = null;
        }
    }
}