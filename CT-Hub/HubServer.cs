using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Net.Sockets;
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
    public readonly JsonStore<ShippingSupplyEntry> ShippingSupplys;
    public readonly JsonStore<QrClassMapping>     QrMappings;
    public readonly JsonStore<CatalogLinkEntry>   CatalogLinks;
    public readonly JsonStore<ColumnDefinition>   Columns;
    public readonly JsonStore<BarcodeLinkEntry>   BarcodeLinks;
    public readonly PdfFolderService  PdfFolder = new();
    public readonly PdfSidecarService PdfSidecar = new();

    private static readonly JsonSerializerOptions _jsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter() }
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

        ShippingSupplys = new JsonStore<ShippingSupplyEntry>(
            Path.Combine(dataDir, "shippingsupplys.json"),
            e => e.Id, WsManager, "shippingsupplys");

        QrMappings = new JsonStore<QrClassMapping>(
            Path.Combine(dataDir, "qr_class_mappings.json"),
            e => e.Id, WsManager, "qr_class_mappings");

        CatalogLinks = new JsonStore<CatalogLinkEntry>(
            Path.Combine(dataDir, "catalog_links.json"),
            e => e.Id, WsManager, "catalog_links");

        Columns = new JsonStore<ColumnDefinition>(
            Path.Combine(dataDir, "columndefinitions.json"),
            e => e.Id, WsManager, "columndefinitions");

        BarcodeLinks = new JsonStore<BarcodeLinkEntry>(
            Path.Combine(dataDir, "barcodelinks.json"),
            e => e.Id, WsManager, "barcodelinks");

        PdfFolder.LoadSavedFolder();
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    public const int DiscoveryPort      = 5052; // UDP port desktop listens on for CT-DISCOVER probes
    public const int DiscoveryReplyPort = 5051; // UDP port phone listens on (desktop broadcasts here)

    public Task StartAsync()
    {
        _cts = new CancellationTokenSource();
        _listener = new HttpListener();
        _listener.Prefixes.Add($"http://+:{Port}/");
        _listener.Start();
        _ = AcceptLoopAsync(_cts.Token);
        _ = DiscoveryLoopAsync(_cts.Token); // always runs: replies to direct CT-DISCOVER probes

        // Start sidecar with error handling — don't block server startup.
        _ = Task.Run(async () =>
        {
            try { await PdfSidecar.StartAsync(_cts.Token); }
            catch (Exception ex)
            {
                Console.Error.WriteLine(
                    $"[HubServer] PDF sidecar failed to start: {ex.Message}");
            }
        });

        return Task.CompletedTask;
    }

    public void Stop()
    {
        StopBroadcast();
        PdfSidecar.Stop();
        _cts?.Cancel();
        _listener?.Stop();
        _listener?.Close();
    }

    // ── UDP discovery broadcaster ─────────────────────────────────────────────
    // Broadcasts "CT-HUB:{Port}" to 255.255.255.255:{DiscoveryReplyPort} every 3 s.
    // Opt-in: call StartBroadcast() to begin, StopBroadcast() to stop.
    // Phone only needs to listen on UDP 5051 — no inbound firewall rule required.

    public bool IsBroadcasting => _broadcastCts != null;
    public DateTime? LastBeaconTime { get; private set; }
    public event Action<bool>? BroadcastStateChanged;
    private CancellationTokenSource? _broadcastCts;

    public void StartBroadcast()
    {
        if (_broadcastCts != null) return;
        _broadcastCts = new CancellationTokenSource();
        BroadcastStateChanged?.Invoke(true);
        _ = BroadcastLoopAsync(_broadcastCts.Token);
    }

    public void StopBroadcast()
    {
        var cts = _broadcastCts;
        _broadcastCts = null;
        cts?.Cancel();
        cts?.Dispose();
        if (cts != null) BroadcastStateChanged?.Invoke(false);
    }

    private async Task BroadcastLoopAsync(CancellationToken ct)
    {
        using var udp = new System.Net.Sockets.UdpClient();
        udp.EnableBroadcast = true;
        var payload = Encoding.UTF8.GetBytes($"CT-HUB:{Port}");
        try
        {
            while (!ct.IsCancellationRequested)
            {
                // Send to every subnet-directed broadcast address on active LAN adapters.
                // 255.255.255.255 (limited broadcast) is filtered by most Wi-Fi APs;
                // subnet-directed (e.g. 192.168.1.255) is forwarded to all subnet hosts.
                foreach (var ep in GetBroadcastEndpoints())
                {
                    try { await udp.SendAsync(payload, payload.Length, ep); }
                    catch { /* skip unreachable adapter */ }
                }
                LastBeaconTime = DateTime.Now;
                await Task.Delay(3_000, ct);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[HubServer] Broadcast error: {ex.Message}");
        }
    }

    // Returns per-adapter subnet-directed broadcast endpoints.
    // Falls back to 255.255.255.255 only if no adapters are found.
    private static List<IPEndPoint> GetBroadcastEndpoints()
    {
        var result = new List<IPEndPoint>();
        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.OperationalStatus != OperationalStatus.Up) continue;
            if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            foreach (var ua in ni.GetIPProperties().UnicastAddresses)
            {
                if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                var mask = ua.IPv4Mask?.GetAddressBytes();
                if (mask == null || mask.Length != 4) continue;
                var ip    = ua.Address.GetAddressBytes();
                var bcast = new byte[4];
                for (int i = 0; i < 4; i++)
                    bcast[i] = (byte)(ip[i] | ~mask[i]);
                result.Add(new IPEndPoint(new IPAddress(bcast), DiscoveryReplyPort));
            }
        }
        if (result.Count == 0)
            result.Add(new IPEndPoint(IPAddress.Broadcast, DiscoveryReplyPort));
        return result;
    }

    // Listens on UDP 5052 for "CT-DISCOVER" probes sent by the phone.
    // Replies immediately so the phone doesn't have to wait for the next 3-second beacon.
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
                var msg = Encoding.UTF8.GetString(result.Buffer).Trim();
                if (msg != "CT-DISCOVER") continue;
                var reply   = Encoding.UTF8.GetBytes($"CT-HUB:{Port}");
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
                // ── Mobile card config ────────────────────────────────────
                case ("GET", "/api/mobile-card-config"):
                    await WriteJsonAsync(res, AppSettings.Instance.MobileCardConfig);
                    break;

                case ("POST", _) when path.StartsWith("/api/mobile-card-config/"):
                {
                    var tableName = path["/api/mobile-card-config/".Length..].ToLowerInvariant();
                    if (string.IsNullOrWhiteSpace(tableName)) { res.StatusCode = 400; break; }
                    var entry = await ReadJsonAsync<CTHub.Services.MobileCardEntry>(req);
                    if (entry is null) { res.StatusCode = 400; break; }
                    AppSettings.Instance.MobileCardConfig[tableName] = entry;
                    AppSettings.Instance.Save();
                    res.StatusCode = 204;
                    break;
                }

                // ── Column definitions ────────────────────────────────────
                case ("GET", _) when path.StartsWith("/api/columns/"):
                {
                    var tableName = path["/api/columns/".Length..].ToLowerInvariant();
                    if (string.IsNullOrWhiteSpace(tableName)) { res.StatusCode = 400; break; }
                    var defs = Columns.GetAll()
                        .Where(c => c.TableName.Equals(tableName, StringComparison.OrdinalIgnoreCase))
                        .OrderBy(c => c.SortOrder)
                        .ToList();
                    await WriteJsonAsync(res, defs);
                    break;
                }

                case ("POST", "/api/columns"):
                {
                    var colDef = await ReadJsonAsync<ColumnDefinition>(req);
                    if (colDef is null || string.IsNullOrWhiteSpace(colDef.TableName)
                        || string.IsNullOrWhiteSpace(colDef.HeaderText))
                    { res.StatusCode = 400; break; }
                    colDef.TableName = colDef.TableName.ToLowerInvariant().Trim();
                    if (string.IsNullOrWhiteSpace(colDef.Id)) colDef.Id = Guid.NewGuid().ToString();
                    if (string.IsNullOrWhiteSpace(colDef.CreatedAtUtc))
                        colDef.CreatedAtUtc = DateTime.UtcNow.ToString("o");
                    await Columns.UpsertAsync(colDef);
                    await WriteJsonAsync(res, colDef);
                    break;
                }

                case ("DELETE", _) when path.StartsWith("/api/columns/"):
                    await Columns.DeleteAsync(path["/api/columns/".Length..]);
                    res.StatusCode = 204; break;

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

                case ("GET", "/api/shippingsupplys"):
                    await WriteJsonAsync(res, ShippingSupplys.GetAll()); break;

                case ("POST", "/api/shippingsupplys"):
                    var ssEntry = await ReadJsonAsync<ShippingSupplyEntry>(req);
                    if (ssEntry is null) { res.StatusCode = 400; break; }
                    await ShippingSupplys.UpsertAsync(ssEntry);
                    await WriteJsonAsync(res, ssEntry); break;

                case ("DELETE", _) when path.StartsWith("/api/shippingsupplys/"):
                    await ShippingSupplys.DeleteAsync(path["/api/shippingsupplys/".Length..]);
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

                case ("GET", "/api/links"):
                {
                    var links = CatalogLinks.GetAll()
                        .Select(x =>
                            new CatalogLinkEntry
                            {
                                Id = x.Id,
                                SourceCatalog = x.SourceCatalog,
                                SourceItemId = x.SourceItemId,
                                SourceItemLabelSnapshot = x.SourceItemLabelSnapshot,
                                ScannedCode = x.ScannedCode,
                                LinkCode = NormalizeLinkCode(x.LinkCode),
                                CreatedAtUtc = x.CreatedAtUtc
                            })
                        .ToList();
                    await WriteJsonAsync(res, links);
                    break;
                }

                case ("POST", "/api/links"):
                {
                    var linkEntry = await ReadJsonAsync<CatalogLinkEntry>(req);
                    if (linkEntry is null || !IsValidSourceCatalog(linkEntry.SourceCatalog)
                        || string.IsNullOrWhiteSpace(linkEntry.SourceItemId)
                        || string.IsNullOrWhiteSpace(linkEntry.ScannedCode))
                    {
                        res.StatusCode = 400;
                        break;
                    }

                    linkEntry.SourceCatalog = NormalizeSourceCatalog(linkEntry.SourceCatalog);
                    linkEntry.SourceItemLabelSnapshot = linkEntry.SourceItemLabelSnapshot?.Trim() ?? string.Empty;
                    linkEntry.SourceItemId = linkEntry.SourceItemId.Trim();
                    linkEntry.ScannedCode = linkEntry.ScannedCode.Trim();
                    linkEntry.LinkCode = NormalizeLinkCode(linkEntry.LinkCode);
                    linkEntry.CreatedAtUtc = string.IsNullOrWhiteSpace(linkEntry.CreatedAtUtc)
                        ? DateTime.UtcNow.ToString("o")
                        : linkEntry.CreatedAtUtc;

                    // enforce one active link per scanned code while still allowing many scanned codes per source item
                    var existing = CatalogLinks.GetAll()
                        .Where(x => x.ScannedCode.Equals(linkEntry.ScannedCode, StringComparison.OrdinalIgnoreCase))
                        .Select(x => x.Id)
                        .ToList();

                    foreach (var existingId in existing)
                        await CatalogLinks.DeleteAsync(existingId);

                    await CatalogLinks.UpsertAsync(linkEntry);
                    await WriteJsonAsync(res, linkEntry);
                    break;
                }

                case ("DELETE", _) when path.StartsWith("/api/links/"):
                    await CatalogLinks.DeleteAsync(path["/api/links/".Length..]);
                    res.StatusCode = 204; break;

                // ── Barcode links ─────────────────────────────────────────
                case ("GET", "/api/barcodelinks"):
                    await WriteJsonAsync(res, BarcodeLinks.GetAll());
                    break;

                case ("POST", "/api/barcodelinks"):
                {
                    var bl = await ReadJsonAsync<BarcodeLinkEntry>(req);
                    if (bl is null
                        || string.IsNullOrWhiteSpace(bl.SourceBarcodeValue)
                        || string.IsNullOrWhiteSpace(bl.SourceColumnId)
                        || string.IsNullOrWhiteSpace(bl.SourceTableName)
                        || string.IsNullOrWhiteSpace(bl.TargetTableName)
                        || string.IsNullOrWhiteSpace(bl.TargetEntryId))
                    { res.StatusCode = 400; break; }

                    if (string.IsNullOrWhiteSpace(bl.Id)) bl.Id = Guid.NewGuid().ToString();
                    if (string.IsNullOrWhiteSpace(bl.CreatedAtUtc))
                        bl.CreatedAtUtc = DateTime.UtcNow.ToString("o");

                    await BarcodeLinks.UpsertAsync(bl);
                    await WriteJsonAsync(res, bl);
                    break;
                }

                case ("DELETE", _) when path.StartsWith("/api/barcodelinks/"):
                    await BarcodeLinks.DeleteAsync(path["/api/barcodelinks/".Length..]);
                    res.StatusCode = 204; break;

                case ("GET", "/api/pdfs/context"):
                    await WriteJsonAsync(res, new { sourceCatalog = PdfFolder.GetActiveSourceCatalog() }); break;

                case ("GET", "/api/pdf-sidecar/status"):
                    await WriteJsonAsync(res, new { available = PdfSidecar.IsAvailable }); break;

                // ── PDF run overrides ─────────────────────────────────────
                case ("GET", _) when path.StartsWith("/api/pdf-overrides/"):
                {
                    var filename = Uri.UnescapeDataString(path["/api/pdf-overrides/".Length..]);
                    var folder   = PdfFolder.CurrentFolder;
                    if (string.IsNullOrWhiteSpace(folder)
                        || filename.Contains('/') || filename.Contains('\\')
                        || filename.Contains(".."))
                    {
                        res.StatusCode = 400; break;
                    }
                    var overridePath = Path.Combine(folder, filename + ".overrides.json");
                    if (!File.Exists(overridePath))
                    {
                        await WriteJsonAsync(res, new { }); break;
                    }
                    var json  = await File.ReadAllTextAsync(overridePath);
                    var bytes = Encoding.UTF8.GetBytes(json);
                    res.ContentType     = "application/json; charset=utf-8";
                    res.ContentLength64 = bytes.Length;
                    await res.OutputStream.WriteAsync(bytes);
                    break;
                }

                case ("POST", _) when path.StartsWith("/api/pdf-overrides/"):
                {
                    var filename = Uri.UnescapeDataString(path["/api/pdf-overrides/".Length..]);
                    var folder   = PdfFolder.CurrentFolder;
                    if (string.IsNullOrWhiteSpace(folder)
                        || filename.Contains('/') || filename.Contains('\\')
                        || filename.Contains(".."))
                    {
                        res.StatusCode = 400; break;
                    }
                    using var reader = new StreamReader(req.InputStream, Encoding.UTF8);
                    var body = await reader.ReadToEndAsync();
                    // Validate it is parseable JSON before writing
                    try { JsonSerializer.Deserialize<object>(body); }
                    catch { res.StatusCode = 400; break; }
                    var overridePath = Path.Combine(folder, filename + ".overrides.json");
                    await File.WriteAllTextAsync(overridePath, body, Encoding.UTF8);
                    res.StatusCode = 204;
                    break;
                }

                // ── PDF folder listing ────────────────────────────────────
                case ("GET", "/api/pdfs"):
                    await WriteJsonAsync(res, PdfFolder.FileNames.ToList()); break;

                // ── PDF metadata (name + last-modified) ───────────────────
                case ("GET", "/api/pdfs/meta"):
                    await WriteJsonAsync(res, PdfFolder.GetFileMeta()); break;

                // ── PDF page count (via sidecar) ──────────────────────────
                case ("GET", _) when path.StartsWith("/api/pdf-pages/"):
                {
                    var filename = Uri.UnescapeDataString(path["/api/pdf-pages/".Length..]);
                    var folder   = PdfFolder.CurrentFolder;
                    if (string.IsNullOrWhiteSpace(folder)
                        || filename.Contains('/') || filename.Contains('\\')
                        || filename.Contains(".."))
                    { res.StatusCode = 400; break; }

                    var fullPath   = Path.GetFullPath(Path.Combine(folder, filename));
                    var folderFull = Path.GetFullPath(folder);
                    if (!fullPath.StartsWith(folderFull + Path.DirectorySeparatorChar))
                    { res.StatusCode = 400; break; }
                    if (!File.Exists(fullPath)) { res.StatusCode = 404; break; }

                    try
                    {
                        var encoded = Uri.EscapeDataString(fullPath);
                        var sidecarResp = await PdfSidecarService.Http.GetAsync(
                            $"/page-count?path={encoded}", ct);
                        var body = await sidecarResp.Content.ReadAsByteArrayAsync(ct);
                        res.ContentType     = "application/json; charset=utf-8";
                        res.ContentLength64 = body.Length;
                        await res.OutputStream.WriteAsync(body, ct);
                    }
                    catch { res.StatusCode = 502; }
                    break;
                }

                // ── PDF page render as JPEG (via sidecar) ─────────────────
                case ("GET", _) when path.StartsWith("/api/pdf-render/"):
                {
                    var filename = Uri.UnescapeDataString(path["/api/pdf-render/".Length..]);
                    var folder   = PdfFolder.CurrentFolder;
                    if (string.IsNullOrWhiteSpace(folder)
                        || filename.Contains('/') || filename.Contains('\\')
                        || filename.Contains(".."))
                    { res.StatusCode = 400; break; }

                    var fullPath   = Path.GetFullPath(Path.Combine(folder, filename));
                    var folderFull = Path.GetFullPath(folder);
                    if (!fullPath.StartsWith(folderFull + Path.DirectorySeparatorChar))
                    { res.StatusCode = 400; break; }
                    if (!File.Exists(fullPath)) { res.StatusCode = 404; break; }

                    var qs = req.QueryString;
                    var page  = qs["page"]  ?? "1";
                    var scale = qs["scale"] ?? "2";
                    try
                    {
                        var encoded = Uri.EscapeDataString(fullPath);
                        var sidecarResp = await PdfSidecarService.Http.GetAsync(
                            $"/render?path={encoded}&page={page}&scale={scale}", ct);
                        var body = await sidecarResp.Content.ReadAsByteArrayAsync(ct);
                        res.ContentType     = "image/jpeg";
                        res.ContentLength64 = body.Length;
                        await res.OutputStream.WriteAsync(body, ct);
                    }
                    catch { res.StatusCode = 502; }
                    break;
                }

                // ── PDF file download ─────────────────────────────────────
                case ("GET", _) when path.StartsWith("/api/pdfs/"):
                {
                    var filename = Uri.UnescapeDataString(path["/api/pdfs/".Length..]);
                    var folder   = PdfFolder.CurrentFolder;

                    // Block path traversal: no directory separators, must resolve inside folder
                    if (string.IsNullOrWhiteSpace(folder)
                        || filename.Contains('/') || filename.Contains('\\')
                        || filename.Contains("..")
                        || (!filename.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase)
                            && !filename.EndsWith(".nl", StringComparison.OrdinalIgnoreCase)))
                    {
                        res.StatusCode = 400; break;
                    }

                    var fullPath = Path.GetFullPath(Path.Combine(folder, filename));
                    var folderFull = Path.GetFullPath(folder);

                    if (!fullPath.StartsWith(folderFull + Path.DirectorySeparatorChar))
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

                // ── PDF word layout (extracted via pdfplumber sidecar) ────────
                case ("GET", _) when path.StartsWith("/api/pdf-words/"):
                {
                    var filename = Uri.UnescapeDataString(path["/api/pdf-words/".Length..]);
                    var folder   = PdfFolder.CurrentFolder;

                    if (string.IsNullOrWhiteSpace(folder)
                        || filename.Contains('/') || filename.Contains('\\')
                        || filename.Contains(".."))
                    {
                        res.StatusCode = 400; break;
                    }

                    var fullPath   = Path.GetFullPath(Path.Combine(folder, filename));
                    var folderFull = Path.GetFullPath(folder);

                    if (!fullPath.StartsWith(folderFull + Path.DirectorySeparatorChar))
                    {
                        res.StatusCode = 400; break;
                    }

                    if (!File.Exists(fullPath)) { res.StatusCode = 404; break; }

                    // Forward to pdfplumber sidecar on localhost:5053.
                    // C# has already validated the path — sidecar trusts us.
                    HttpResponseMessage sidecarResp;
                    try
                    {
                        var encoded = Uri.EscapeDataString(fullPath);
                        sidecarResp = await PdfSidecarService.Http.GetAsync(
                            $"/words?path={encoded}", ct);
                    }
                    catch
                    {
                        // Sidecar unreachable — iOS will fall back to on-device PDFKit.
                        res.StatusCode = 503; break;
                    }

                    if (!sidecarResp.IsSuccessStatusCode)
                    {
                        res.StatusCode = (int)sidecarResp.StatusCode; break;
                    }

                    var jsonBytes = await sidecarResp.Content.ReadAsByteArrayAsync(ct);
                    res.ContentType     = "application/json; charset=utf-8";
                    res.ContentLength64 = jsonBytes.Length;
                    await res.OutputStream.WriteAsync(jsonBytes, ct);
                    break;
                }

                // ── PDF plain text (all pages) — for bin extraction on Android ──
                case ("GET", _) when path.StartsWith("/api/pdf-text/"):
                {
                    var filename = Uri.UnescapeDataString(path["/api/pdf-text/".Length..]);
                    var folder   = PdfFolder.CurrentFolder;
                    if (string.IsNullOrWhiteSpace(folder)
                        || filename.Contains('/') || filename.Contains('\\')
                        || filename.Contains(".."))
                    { res.StatusCode = 400; break; }

                    var fullPath   = Path.GetFullPath(Path.Combine(folder, filename));
                    var folderFull = Path.GetFullPath(folder);
                    if (!fullPath.StartsWith(folderFull + Path.DirectorySeparatorChar))
                    { res.StatusCode = 400; break; }
                    if (!File.Exists(fullPath)) { res.StatusCode = 404; break; }

                    try
                    {
                        var encoded     = Uri.EscapeDataString(fullPath);
                        var sidecarResp = await PdfSidecarService.Http.GetAsync(
                            $"/text?path={encoded}", ct);
                        var body = await sidecarResp.Content.ReadAsByteArrayAsync(ct);
                        res.ContentType     = "application/json; charset=utf-8";
                        res.ContentLength64 = body.Length;
                        await res.OutputStream.WriteAsync(body, ct);
                    }
                    catch { res.StatusCode = 502; }
                    break;
                }

                // ── Static files (wwwroot) ────────────────────────────────────
                case ("GET", _) when !path.StartsWith("/api/"):
                {
                    var wwwroot  = Path.Combine(AppContext.BaseDirectory, "wwwroot");
                    var relative = path == "" || path == "/" ? "index.html" : path.TrimStart('/');
                    var fullPath = Path.GetFullPath(Path.Combine(wwwroot, relative));

                    // Block path traversal
                    if (!fullPath.StartsWith(Path.GetFullPath(wwwroot) + Path.DirectorySeparatorChar)
                        && !fullPath.Equals(Path.GetFullPath(wwwroot), StringComparison.OrdinalIgnoreCase))
                    {
                        res.StatusCode = 403; break;
                    }

                    if (!File.Exists(fullPath)) { res.StatusCode = 404; break; }

                    var ext = Path.GetExtension(fullPath).ToLowerInvariant();
                    res.ContentType = ext switch
                    {
                        ".html" => "text/html; charset=utf-8",
                        ".js"   => "application/javascript; charset=utf-8",
                        ".mjs"  => "application/javascript; charset=utf-8",
                        ".css"  => "text/css; charset=utf-8",
                        ".json" => "application/json; charset=utf-8",
                        ".png"  => "image/png",
                        ".jpg"  => "image/jpeg",
                        ".svg"  => "image/svg+xml",
                        _       => "application/octet-stream"
                    };

                    var bytes = await File.ReadAllBytesAsync(fullPath);
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
        var json  = JsonSerializer.Serialize(data, _jsonOpts);
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

    private static bool IsValidSourceCatalog(string? sourceCatalog)
    {
        if (string.IsNullOrWhiteSpace(sourceCatalog)) return false;
        return sourceCatalog.Equals("chase_tactical", StringComparison.OrdinalIgnoreCase)
            || sourceCatalog.Equals("tough_hook", StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizeSourceCatalog(string sourceCatalog)
    {
        return sourceCatalog.Equals("tough_hook", StringComparison.OrdinalIgnoreCase)
            ? "tough_hook"
            : "chase_tactical";
    }

    private static string NormalizeLinkCode(string? linkCode)
    {
        var trimmed = linkCode?.Trim() ?? string.Empty;
        return string.IsNullOrWhiteSpace(trimmed) ? "?-000" : trimmed;
    }
}

