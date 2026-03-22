using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace CTHub.Services;

/// <summary>
/// Keeps track of all live WebSocket connections and broadcasts
/// JSON messages to every connected client.
/// </summary>
public sealed class WebSocketManager
{
    private readonly ConcurrentDictionary<string, WebSocket> _sockets = new();

    public int ConnectedCount => _sockets.Count;

    public void Register(string id, WebSocket ws) => _sockets[id] = ws;

    public void Unregister(string id) => _sockets.TryRemove(id, out _);

    /// <summary>Broadcast a UTF-8 JSON payload to all open sockets.</summary>
    public async Task BroadcastAsync(object payload)
    {
        var json = JsonSerializer.Serialize(payload);
        var bytes = Encoding.UTF8.GetBytes(json);
        var segment = new ArraySegment<byte>(bytes);

        var dead = new List<string>();

        foreach (var (id, ws) in _sockets)
        {
            if (ws.State == WebSocketState.Open)
            {
                try
                {
                    await ws.SendAsync(segment, WebSocketMessageType.Text, true, CancellationToken.None);
                }
                catch
                {
                    dead.Add(id);
                }
            }
            else
            {
                dead.Add(id);
            }
        }

        foreach (var id in dead) Unregister(id);
    }
}
