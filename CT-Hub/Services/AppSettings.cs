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
    public double PdfEditorPanelRatio    { get; set; }

    /// <summary>
    /// Persisted column widths and display-indexes, keyed by DataGrid.Name.
    /// </summary>
    public Dictionary<string, List<ColumnLayoutEntry>> ColumnLayouts { get; set; } = new();

    /// <summary>
    /// User-renamed static column headers. Key = "GridName|OriginalHeader", Value = renamed label.
    /// </summary>
    public Dictionary<string, string> StaticColumnLabels { get; set; } = new();

    /// <summary>
    /// IDs of seed column definitions that have been applied at least once.
    /// Prevents re-seeding after a user deliberately deletes a seeded column.
    /// </summary>
    public HashSet<string> AppliedSeedIds { get; set; } = new();

    /// <summary>
    /// Per-table card layout for the Android scan picker.
    /// Key = tableName (lowercase). Seeded with sensible defaults on first run.
    /// </summary>
    public Dictionary<string, MobileCardEntry> MobileCardConfig { get; set; } = new();

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

public sealed class ColumnLayoutEntry
{
    public string Key          { get; set; } = string.Empty;
    public double Width        { get; set; } = double.NaN;
    public int    DisplayIndex { get; set; }
}

/// <summary>
/// Defines how Android renders a single-row card in the scan entry picker.
/// All fields are BindingPath values (e.g. "Label", "Bin", "Qty").
/// </summary>
public sealed class MobileCardEntry
{
    /// <summary>Primary (bold) title field. Null = first non-ID column.</summary>
    public string? Row1  { get; set; }

    /// <summary>Secondary line fields, joined with  ·  separator. Up to 2 entries.</summary>
    public List<string> Row2  { get; set; } = new();

    /// <summary>Badge pill field (e.g. Qty). Null = no badge.</summary>
    public string? Badge { get; set; }
}
