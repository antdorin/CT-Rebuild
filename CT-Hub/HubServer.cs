using System.IO;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using CTHub.Models;
using CTHub.Services;

namespace CTHub;

/// <summary>
/// Self-hosted HTTP + WebSocket server running inside the WPF process.
/// Uses HttpListener (no SDK dependency) so it works in Microsoft.NET.Sdk (WPF).
/// Port: 5050.  Requires "Run as Administrator" OR a one-time netsh reservation:
///   netsh http add urlacl url=http://+:5050/ user=Everyone
/// </summary>
public sealed class HubServer
{
    public const int Port = 5050;
    private HttpListener? _listener;
    private CancellationTokenSource? _cts;

    /// Fired on the thread-pool whenever a new WebSocket client connects.
    /// Arg is the client's remote IP address string.
    public event Action<string>? ClientConnected;

    public readonly WebSocketManager  WsManager = new();
    public readonly JsonStore<ChaseTacticalEntry> ChaseTactical;
    public readonly JsonStore<ToughHookEntry>     ToughHooks;
    public readonly JsonStore<QrClassMapping>     QrMappings;
    public readonly PdfFolderService  PdfFolder = new();

    private static readonly JsonSerializerOptions _jsonOpts = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public HubServer()
    {
        var dataDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "CT-Hub");

        ChaseTactical = new JsonStore<ChaseTacticalEntry>(
            Path.Combine(dataDir, "chasetactical.json"),
            e => e.Id, WsManager, "chasetactical");

        ToughHooks = new JsonStore<ToughHookEntry>(
            Path.Combine(dataDir, "toughhooks.json"),
            e => e.Id, WsManager, "toughhooks");

        QrMappings = new JsonStore<QrClassMapping>(
            Path.Combine(dataDir, "qr_class_mappings.json"),
            e => e.Id, WsManager, "qr_class_mappings");

        PdfFolder.LoadSavedFolder();
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    public const int DiscoveryPort = 5052;      // UDP port desktop listens on
    public const int DiscoveryReplyPort = 5051; // UDP port phone listens on

    public Task StartAsync()
    {
        _cts = new CancellationTokenSource();
        _listener = new HttpListener();
        _listener.Prefixes.Add($"http://+:{Port}/");
        _listener.Start();
        _ = AcceptLoopAsync(_cts.Token);
        _ = DiscoveryLoopAsync(_cts.Token);
        return Task.CompletedTask;
    }

    public void Stop()
    {
        _cts?.Cancel();
        _listener?.Stop();
        _listener?.Close();
    }

    // ── UDP discovery responder ───────────────────────────────────────────────
    // Listens for "CT-DISCOVER" on UDP 5052, replies "CT-HUB:{Port}" back to
    // the sender on port 5051. Zero overhead when idle — only answers when asked.

    private async Task DiscoveryLoopAsync(CancellationToken ct)
    {
        using var udp = new System.Net.Sockets.UdpClient();
        udp.Client.SetSocketOption(
            System.Net.Sockets.SocketOptionLevel.Socket,
            System.Net.Sockets.SocketOptionName.ReuseAddress, true);
        udp.Client.Bind(new IPEndPoint(IPAddress.Any, DiscoveryPort));

        while (!ct.IsCancellationRequested)
        {
            try
            {
                var result = await udp.ReceiveAsync(ct);
                var msg = System.Text.Encoding.UTF8.GetString(result.Buffer).Trim();
                if (msg != "CT-DISCOVER") continue;

                var reply = System.Text.Encoding.UTF8.GetBytes($"CT-HUB:{Port}");
                var replyEp = new IPEndPoint(result.RemoteEndPoint.Address, DiscoveryReplyPort);
                await udp.SendAsync(reply, reply.Length, replyEp);
            }
            catch (OperationCanceledException) { break; }
            catch { /* ignore malformed packets */ }
        }
    }

    // ── Accept loop ───────────────────────────────────────────────────────────

    private async Task AcceptLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            HttpListenerContext ctx;
            try { ctx = await _listener!.GetContextAsync(); }
            catch { break; }
            _ = HandleContextAsync(ctx, ct);
        }
    }

    private async Task HandleContextAsync(HttpListenerContext ctx, CancellationToken ct)
    {
        var req  = ctx.Request;
        var res  = ctx.Response;
        var path = req.Url?.AbsolutePath.TrimEnd('/') ?? "";

        try
        {
            // ── WebSocket upgrade ─────────────────────────────────────────────
            if (req.IsWebSocketRequest)
            {
                var wsCtx = await ctx.AcceptWebSocketAsync(null);
                var ws    = wsCtx.WebSocket;
                var id         = Guid.NewGuid().ToString();
                var clientIp   = ctx.Request.RemoteEndPoint?.Address?.ToString() ?? "unknown";
                WsManager.Register(id, ws);
                ClientConnected?.Invoke(clientIp);

                var buf = new byte[1024];
                while (ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
                {
                    try
                    {
                        var r = await ws.ReceiveAsync(buf, ct);
                        if (r.MessageType == WebSocketMessageType.Close) break;
                    }
                    catch { break; }
                }

                WsManager.Unregister(id);
                if (ws.State == WebSocketState.Open)
                    await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None);
                return;
            }

            // ── REST routing ──────────────────────────────────────────────────
            switch ((req.HttpMethod, path))
            {
                case ("GET", "/api/chasetactical"):
                    await WriteJsonAsync(res, ChaseTactical.GetAll()); break;

                case ("POST", "/api/chasetactical"):
                    var ctEntry = await ReadJsonAsync<ChaseTacticalEntry>(req);
                    if (ctEntry is null) { res.StatusCode = 400; break; }
                    await ChaseTactical.UpsertAsync(ctEntry);
                    await WriteJsonAsync(res, ctEntry); break;

                case ("DELETE", _) when path.StartsWith("/api/chasetactical/"):
                    await ChaseTactical.DeleteAsync(path["/api/chasetactical/".Length..]);
                    res.StatusCode = 204; break;

                case ("GET", "/api/toughhooks"):
                    await WriteJsonAsync(res, ToughHooks.GetAll()); break;

                case ("POST", "/api/toughhooks"):
                    var thEntry = await ReadJsonAsync<ToughHookEntry>(req);
                    if (thEntry is null) { res.StatusCode = 400; break; }
                    await ToughHooks.UpsertAsync(thEntry);
                    await WriteJsonAsync(res, thEntry); break;

                case ("DELETE", _) when path.StartsWith("/api/toughhooks/"):
                    await ToughHooks.DeleteAsync(path["/api/toughhooks/".Length..]);
                    res.StatusCode = 204; break;

                case ("GET", "/api/qr_class_mappings"):
                    await WriteJsonAsync(res, QrMappings.GetAll()); break;

                case ("POST", "/api/qr_class_mappings"):
                    var qrEntry = await ReadJsonAsync<QrClassMapping>(req);
                    if (qrEntry is null) { res.StatusCode = 400; break; }
                    await QrMappings.UpsertAsync(qrEntry);
                    await WriteJsonAsync(res, qrEntry); break;

                case ("DELETE", _) when path.StartsWith("/api/qr_class_mappings/"):
                    await QrMappings.DeleteAsync(path["/api/qr_class_mappings/".Length..]);
                    res.StatusCode = 204; break;

                // ── PDF folder listing ────────────────────────────────────
                case ("GET", "/api/pdfs"):
                    await WriteJsonAsync(res, PdfFolder.FileNames.ToList()); break;

                // ── PDF file download ─────────────────────────────────────
                case ("GET", _) when path.StartsWith("/api/pdfs/"):
                {
                    var filename = Uri.UnescapeDataString(path["/api/pdfs/".Length..]);
                    var folder   = PdfFolder.CurrentFolder;

                    // Block path traversal: no directory separators, must resolve inside folder
                    if (string.IsNullOrWhiteSpace(folder)
                        || filename.Contains('/') || filename.Contains('\\')
                        || filename.Contains("..")
                        || !filename.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase))
                    {
                        res.StatusCode = 400; break;
                    }

                    var fullPath = Path.GetFullPath(Path.Combine(folder, filename));
                    var folderFull = Path.GetFullPath(folder);

                    if (!fullPath.StartsWith(folderFull + Path.DirectorySeparatorChar)
                        && !fullPath.Equals(folderFull, StringComparison.OrdinalIgnoreCase))
                    {
                        res.StatusCode = 400; break;
                    }

                    if (!File.Exists(fullPath)) { res.StatusCode = 404; break; }

                    var bytes = await File.ReadAllBytesAsync(fullPath);
                    res.ContentType     = "application/pdf";
                    res.ContentLength64 = bytes.Length;
                    await res.OutputStream.WriteAsync(bytes);
                    break;
                }

                default:
                    res.StatusCode = 404; break;
            }
        }
        catch (Exception ex)
        {
            res.StatusCode = 500;
            System.Diagnostics.Debug.WriteLine($"[HubServer] {ex.Message}");
        }
        finally
        {
            try { res.Close(); } catch { /* ignored */ }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static async Task WriteJsonAsync(HttpListenerResponse res, object data)
    {
        var json  = JsonSerializer.Serialize(data);
        var bytes = Encoding.UTF8.GetBytes(json);
        res.ContentType     = "application/json; charset=utf-8";
        res.ContentLength64 = bytes.Length;
        await res.OutputStream.WriteAsync(bytes);
    }

    private static async Task<T?> ReadJsonAsync<T>(HttpListenerRequest req)
    {
        try { return await JsonSerializer.DeserializeAsync<T>(req.InputStream, _jsonOpts); }
        catch { return default; }
    }
}

