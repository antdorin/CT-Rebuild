using System.Collections.Concurrent;
using System.IO;
using System.Net.Http;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace CTHub.Services;

public sealed class CdpTarget
{
    public string Id { get; init; } = string.Empty;
    public string Type { get; init; } = string.Empty;
    public string Title { get; init; } = string.Empty;
    public string Url { get; init; } = string.Empty;
    public string WebSocketDebuggerUrl { get; init; } = string.Empty;

    public override string ToString()
    {
        var title = string.IsNullOrWhiteSpace(Title) ? "(untitled)" : Title;
        return $"{title}  [{Type}]";
    }
}

public sealed class CdpNetworkEvent
{
    public string Url { get; init; } = string.Empty;
    public int Status { get; init; }
    public string MimeType { get; init; } = string.Empty;
    public string RequestId { get; init; } = string.Empty;
}

public sealed class CdpDevToolsService : IAsyncDisposable
{
    private readonly ConcurrentDictionary<int, TaskCompletionSource<JsonElement>> _pending = new();
    private ClientWebSocket? _socket;
    private CancellationTokenSource? _receiveLoopCts;
    private Task? _receiveLoopTask;
    private int _nextCommandId = 1;

    public event Action<string>? Log;
    public event Action<CdpNetworkEvent>? NetworkEventReceived;

    public static async Task<IReadOnlyList<CdpTarget>> GetTargetsAsync(string endpoint, CancellationToken cancellationToken = default)
    {
        var baseUri = endpoint.Trim().TrimEnd('/');
        if (!baseUri.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
            !baseUri.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            baseUri = "http://" + baseUri;
        }

        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
        using var stream = await client.GetStreamAsync($"{baseUri}/json", cancellationToken);

        var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        if (doc.RootElement.ValueKind != JsonValueKind.Array)
            return [];

        var targets = new List<CdpTarget>();
        foreach (var item in doc.RootElement.EnumerateArray())
        {
            var type = GetString(item, "type");
            var wsUrl = GetString(item, "webSocketDebuggerUrl");
            if (!string.Equals(type, "page", StringComparison.OrdinalIgnoreCase))
                continue;
            if (string.IsNullOrWhiteSpace(wsUrl))
                continue;

            targets.Add(new CdpTarget
            {
                Id = GetString(item, "id"),
                Type = type,
                Title = GetString(item, "title"),
                Url = GetString(item, "url"),
                WebSocketDebuggerUrl = wsUrl
            });
        }

        return targets;
    }

    public async Task ConnectAsync(string webSocketDebuggerUrl, CancellationToken cancellationToken = default)
    {
        await DisconnectAsync();

        _socket = new ClientWebSocket();
        await _socket.ConnectAsync(new Uri(webSocketDebuggerUrl), cancellationToken);
        _receiveLoopCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _receiveLoopTask = Task.Run(() => ReceiveLoopAsync(_receiveLoopCts.Token), _receiveLoopCts.Token);

        await SendCommandAsync("Network.enable", null, cancellationToken);
        Log?.Invoke("Connected to Chrome tab.");
    }

    public async Task DisconnectAsync()
    {
        if (_receiveLoopCts is not null)
        {
            _receiveLoopCts.Cancel();
            _receiveLoopCts.Dispose();
            _receiveLoopCts = null;
        }

        if (_socket is not null)
        {
            try
            {
                if (_socket.State == WebSocketState.Open)
                    await _socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Disconnect", CancellationToken.None);
            }
            catch
            {
                // Ignore close failures.
            }

            _socket.Dispose();
            _socket = null;
        }

        if (_receiveLoopTask is not null)
        {
            try
            {
                await _receiveLoopTask;
            }
            catch
            {
                // Ignore loop cancellation errors.
            }
            _receiveLoopTask = null;
        }

        foreach (var kv in _pending)
            kv.Value.TrySetCanceled();
        _pending.Clear();
    }

    public async ValueTask DisposeAsync()
    {
        await DisconnectAsync();
    }

    private async Task<JsonElement?> SendCommandAsync(string method, object? parameters, CancellationToken cancellationToken)
    {
        if (_socket is null || _socket.State != WebSocketState.Open)
            throw new InvalidOperationException("CDP socket is not connected.");

        var id = Interlocked.Increment(ref _nextCommandId);
        var tcs = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pending[id] = tcs;

        var payload = JsonSerializer.Serialize(new
        {
            id,
            method,
            @params = parameters
        });

        var bytes = Encoding.UTF8.GetBytes(payload);
        await _socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, cancellationToken);

        using var reg = cancellationToken.Register(() => tcs.TrySetCanceled(cancellationToken));
        var result = await tcs.Task;
        return result;
    }

    private async Task ReceiveLoopAsync(CancellationToken cancellationToken)
    {
        if (_socket is null)
            return;

        var buffer = new byte[32 * 1024];
        while (!cancellationToken.IsCancellationRequested && _socket.State == WebSocketState.Open)
        {
            using var ms = new MemoryStream();
            WebSocketReceiveResult receive;
            do
            {
                receive = await _socket.ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken);
                if (receive.MessageType == WebSocketMessageType.Close)
                    return;
                ms.Write(buffer, 0, receive.Count);
            } while (!receive.EndOfMessage);

            if (receive.MessageType != WebSocketMessageType.Text)
                continue;

            var json = Encoding.UTF8.GetString(ms.ToArray());
            HandleIncoming(json);
        }
    }

    private void HandleIncoming(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.TryGetProperty("id", out var idProp) && idProp.TryGetInt32(out var id))
            {
                if (_pending.TryRemove(id, out var tcs))
                {
                    if (root.TryGetProperty("result", out var resultProp))
                        tcs.TrySetResult(resultProp.Clone());
                    else if (root.TryGetProperty("error", out _))
                        tcs.TrySetException(new InvalidOperationException($"CDP command failed: {json}"));
                    else
                        tcs.TrySetResult(default);
                }

                return;
            }

            if (!root.TryGetProperty("method", out var methodProp))
                return;

            var method = methodProp.GetString() ?? string.Empty;
            if (!string.Equals(method, "Network.responseReceived", StringComparison.Ordinal))
                return;

            if (!root.TryGetProperty("params", out var paramsProp))
                return;

            var requestId = GetString(paramsProp, "requestId");
            if (!paramsProp.TryGetProperty("response", out var response))
                return;

            var evt = new CdpNetworkEvent
            {
                RequestId = requestId,
                Url = GetString(response, "url"),
                Status = response.TryGetProperty("status", out var statusProp)
                    ? (int)Math.Round(statusProp.GetDouble())
                    : 0,
                MimeType = GetString(response, "mimeType")
            };

            NetworkEventReceived?.Invoke(evt);
        }
        catch (Exception ex)
        {
            Log?.Invoke($"CDP parse error: {ex.Message}");
        }
    }

    private static string GetString(JsonElement el, string propName)
    {
        return el.TryGetProperty(propName, out var prop) && prop.ValueKind == JsonValueKind.String
            ? (prop.GetString() ?? string.Empty)
            : string.Empty;
    }
}
