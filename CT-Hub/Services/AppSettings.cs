using System.IO;
using System.Text.Json;

namespace CTHub.Services;

/// <summary>
/// Persists application-level settings to %APPDATA%\CT-Hub\settings.json.
/// Loaded once on startup; saved whenever a property changes.
/// </summary>
public sealed class AppSettings
{
    private static readonly string _path = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "CT-Hub", "settings.json");

    private static readonly JsonSerializerOptions _opts = new() { WriteIndented = true };

    // ── Persisted data ────────────────────────────────────────────────────────

    public string SelectedPdfFolder { get; set; } = string.Empty;
    public string DevChromeEndpoint { get; set; } = "http://127.0.0.1:9222";
    public string DevBrowserKind { get; set; } = "Chrome";
    public string DevBrowserExecutablePath { get; set; } = string.Empty;
    public bool DevUseLocalBrowserData { get; set; } = false;
    public string DevBrowserUserDataDir { get; set; } = string.Empty;
    public string DevBrowserProfileDirectory { get; set; } = "Default";
    public bool DevAutoConnectFirstTab { get; set; } = true;
    public bool DevUseProfileSnapshot { get; set; } = true;
    public double PdfEditorFileListRatio { get; set; }
    public double PdfEditorPanelRatio { get; set; }

    // ── Singleton ─────────────────────────────────────────────────────────────

    public static AppSettings Instance { get; } = Load();

    private static AppSettings Load()
    {
        try
        {
            if (File.Exists(_path))
            {
                var text = File.ReadAllText(_path);
                return JsonSerializer.Deserialize<AppSettings>(text) ?? new AppSettings();
            }
        }
        catch { /* corrupt — start fresh */ }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var tmp = _path + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(this, _opts));
            File.Move(tmp, _path, overwrite: true);
        }
        catch { /* best-effort */ }
    }
}
