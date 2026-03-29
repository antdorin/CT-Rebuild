using System.Diagnostics;
using System.IO;
using System.Net.Http;

namespace CTHub.Services;

/// <summary>
/// Manages the lifecycle of the pdf_service Python sidecar process and
/// provides an <see cref="HttpClient"/> pre-configured to talk to it.
/// 
/// The sidecar listens on 127.0.0.1:5053 (localhost only) and is
/// unreachable by the iOS device — only this C# process communicates with it.
/// 
/// Endpoints forwarded via HubServer:
///   GET  /words?path={fullPath}   → word-layout JSON
///   DELETE /cache?path={fullPath} → cache invalidation
///   GET  /health                  → readiness check
/// </summary>
public sealed class PdfSidecarService : IDisposable
{
    public const int Port = 5053;

    private static readonly string BaseUrl = $"http://127.0.0.1:{Port}";

    // Shared HttpClient — safe for concurrent use, long-lived.
    public static readonly HttpClient Http = new()
    {
        BaseAddress = new Uri(BaseUrl),
        Timeout     = TimeSpan.FromSeconds(30),
    };

    private Process? _process;
    private readonly SemaphoreSlim _startLock = new(1, 1);

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /// <summary>
    /// Locates and starts the sidecar process, then waits up to 10 s for it to
    /// become ready.  Safe to call multiple times (no-op if already running).
    /// </summary>
    public async Task StartAsync(CancellationToken ct = default)
    {
        await _startLock.WaitAsync(ct);
        try
        {
            if (_process is { HasExited: false }) return;

            var (fileName, args) = ResolveLaunchArgs();
            var psi = new ProcessStartInfo(fileName, args)
            {
                UseShellExecute        = false,
                CreateNoWindow         = true,
                RedirectStandardOutput = false,
                RedirectStandardError  = false,
                Environment            = { ["PDF_SIDECAR_PORT"] = Port.ToString() },
            };

            _process = Process.Start(psi)
                ?? throw new InvalidOperationException("Failed to start pdf_service process.");

            await WaitForReadyAsync(ct);
        }
        finally
        {
            _startLock.Release();
        }
    }

    /// <summary>Kills the sidecar process if it is running.</summary>
    public void Stop()
    {
        try
        {
            if (_process is { HasExited: false })
                _process.Kill(entireProcessTree: true);
        }
        catch { /* process may have already exited */ }
        finally
        {
            _process?.Dispose();
            _process = null;
        }
    }

    public void Dispose()
    {
        Stop();
        _startLock.Dispose();
    }

    // ── Cache invalidation (called by PdfFolderService FileSystemWatcher) ─────

    /// <summary>
    /// Tells the sidecar to drop its cached result for <paramref name="fullPath"/>.
    /// Fire-and-forget — failures are silently swallowed.
    /// </summary>
    public static void InvalidateCache(string fullPath)
    {
        _ = Task.Run(async () =>
        {
            try
            {
                var encoded = Uri.EscapeDataString(fullPath);
                await Http.DeleteAsync($"/cache?path={encoded}");
            }
            catch { /* sidecar may not be running yet */ }
        });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// <summary>
    /// Returns (fileName, args) to launch the sidecar.
    /// Prefers pdf_service.exe next to the running assembly; falls back to
    /// running the .py script directly via the system Python interpreter.
    /// </summary>
    private static (string fileName, string args) ResolveLaunchArgs()
    {
        var baseDir = AppContext.BaseDirectory;
        var exe     = Path.Combine(baseDir, "pdf_service.exe");
        if (File.Exists(exe))
            return (exe, string.Empty);

        // Dev fallback: run the script with the system Python.
        var script = Path.GetFullPath(
            Path.Combine(baseDir, "..", "..", "..", "..", "pdf_service", "pdf_service.py"));

        if (!File.Exists(script))
            throw new FileNotFoundException(
                "pdf_service.exe not found and dev script path does not exist. " +
                $"Expected: {exe}  or  {script}");

        return ("python", $"\"{script}\"");
    }

    /// <summary>
    /// Polls GET /health every 500 ms until the sidecar responds or 10 s elapses.
    /// </summary>
    private static async Task WaitForReadyAsync(CancellationToken ct)
    {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        using var probe = new HttpClient { BaseAddress = new Uri(BaseUrl), Timeout = TimeSpan.FromSeconds(1) };

        while (DateTime.UtcNow < deadline)
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                var resp = await probe.GetAsync("/health", ct);
                if (resp.IsSuccessStatusCode) return;
            }
            catch { /* not ready yet */ }

            await Task.Delay(500, ct);
        }

        throw new TimeoutException("pdf_service sidecar did not become ready within 10 seconds.");
    }
}
