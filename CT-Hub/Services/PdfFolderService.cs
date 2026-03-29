using System.Collections.ObjectModel;
using System.IO;
using System.Text.RegularExpressions;

namespace CTHub.Services;

/// <summary>
/// Tracks a folder on disk and exposes a live list of .pdf filenames found in it.
/// Fires <see cref="FilesChanged"/> whenever the folder contents change.
/// </summary>
public sealed class PdfFolderService : IDisposable
{
    private FileSystemWatcher? _watcher;
    private string _folder = string.Empty;

    /// <summary>Filename-only list (not full paths), UI-thread-safe via Dispatcher.</summary>
    public ObservableCollection<string> FileNames { get; } = new();

    /// <summary>Rows for desktop grid: filename + parsed sales order + import timestamp.</summary>
    public ObservableCollection<PdfFileRow> FileRows { get; } = new();

    /// <summary>Raised on the thread-pool when the file list changes.</summary>
    public event Action? FilesChanged;

    // ── Folder selection ──────────────────────────────────────────────────────

    public string CurrentFolder => _folder;

    public void SetFolder(string folderPath)
    {
        _folder = folderPath;

        // Persist across restarts
        AppSettings.Instance.SelectedPdfFolder = folderPath;
        AppSettings.Instance.Save();

        SetupWatcher(folderPath);
        Refresh();
    }

    /// <summary>Call once on startup to reload the last-used folder.</summary>
    public void LoadSavedFolder()
    {
        var saved = AppSettings.Instance.SelectedPdfFolder;
        if (!string.IsNullOrWhiteSpace(saved) && Directory.Exists(saved))
            SetFolder(saved);
    }

    // ── Internals ─────────────────────────────────────────────────────────────

    private void Refresh()
    {
        var files = Directory.Exists(_folder)
            ? Directory.GetFiles(_folder, "*", SearchOption.TopDirectoryOnly)
                       .Where(f => f.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase)
                                || f.EndsWith(".nl",  StringComparison.OrdinalIgnoreCase))
                       .Select(f => new FileInfo(f))
                       .Where(fi => fi.Exists)
                       .OrderBy(fi => fi.Name, StringComparer.OrdinalIgnoreCase)
                       .ToList()
            : new List<FileInfo>();

        // Update on the UI thread if a dispatcher is available
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher != null && !dispatcher.CheckAccess())
        {
            dispatcher.Invoke(() => SyncList(files));
        }
        else
        {
            SyncList(files);
        }

        FilesChanged?.Invoke();
    }

    private void SyncList(IList<FileInfo> files)
    {
        FileNames.Clear();
        FileRows.Clear();

        foreach (var fi in files)
        {
            FileNames.Add(fi.Name);
            FileRows.Add(new PdfFileRow(
                fi.Name,
                ExtractSalesOrders(fi.Name),
                fi.LastWriteTime));
        }
    }

    private static string ExtractSalesOrders(string fileName)
    {
        var baseName = Path.GetFileNameWithoutExtension(fileName);
        if (string.IsNullOrWhiteSpace(baseName)) return string.Empty;

        var soMatches = Regex.Matches(baseName, @"\bSO-[A-Za-z0-9]+-[A-Za-z0-9]+\b", RegexOptions.IgnoreCase)
            .Select(m => m.Value.Replace("_", "-").Replace(" ", "").ToUpperInvariant())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (soMatches.Count > 0)
            return string.Join(", ", soMatches);

        var numeric = Regex.Matches(baseName, @"\b\d{5,}\b")
            .Select(m => m.Value)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        return numeric.Count > 0 ? string.Join(", ", numeric) : string.Empty;
    }

    private void SetupWatcher(string folderPath)
    {
        _watcher?.Dispose();
        if (!Directory.Exists(folderPath)) return;

        _watcher = new FileSystemWatcher(folderPath)
        {
            Filter = "*",
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite,
            EnableRaisingEvents = true
        };
        _watcher.Created += (_, _) => Refresh();
        _watcher.Deleted += (_, e) => { PdfSidecarService.InvalidateCache(e.FullPath); Refresh(); };
        _watcher.Renamed += (_, e) => { PdfSidecarService.InvalidateCache(e.OldFullPath); Refresh(); };
        _watcher.Changed += (_, e) => PdfSidecarService.InvalidateCache(e.FullPath);
    }

    public void Dispose() => _watcher?.Dispose();

    public string GetActiveSourceCatalog()
    {
        if (string.IsNullOrWhiteSpace(_folder)) return "chase_tactical";

        var folderName = Path.GetFileName(_folder);
        if (string.IsNullOrWhiteSpace(folderName)) return "chase_tactical";

        if (folderName.Contains("tough hook", StringComparison.OrdinalIgnoreCase)
            || folderName.Contains("toughhook", StringComparison.OrdinalIgnoreCase))
            return "tough_hook";

        return "chase_tactical";
    }

    // ── Metadata ──────────────────────────────────────────────────────────────

    /// Returns filename + last-modified (UTC ISO 8601) for each PDF in the folder.
    public IReadOnlyList<PdfFileMeta> GetFileMeta()
    {
        if (string.IsNullOrEmpty(_folder) || !Directory.Exists(_folder))
            return Array.Empty<PdfFileMeta>();

        var sourceCatalog = GetActiveSourceCatalog();

        return Directory.GetFiles(_folder, "*", SearchOption.TopDirectoryOnly)
            .Where(f => f.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase)
                     || f.EndsWith(".nl",  StringComparison.OrdinalIgnoreCase))
            .Select(f => new FileInfo(f))
            .Where(fi => fi.Exists)
            .OrderBy(fi => fi.Name, StringComparer.OrdinalIgnoreCase)
            .Select(fi => new PdfFileMeta(fi.Name, fi.LastWriteTimeUtc.ToString("o"), sourceCatalog))
            .ToList();
    }
}

/// <summary>Desktop PDF row with metadata extracted from the source folder file.</summary>
public sealed record PdfFileRow(string Name, string SalesOrders, DateTime ImportDateTime);

/// <summary>Filename + UTC last-modified timestamp for a single PDF.</summary>
public sealed record PdfFileMeta(string Name, string Modified, string SourceCatalog);
