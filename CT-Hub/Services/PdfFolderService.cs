using System.Collections.ObjectModel;
using System.IO;

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
            ? Directory.GetFiles(_folder, "*.pdf", SearchOption.TopDirectoryOnly)
                       .Select(Path.GetFileName)
                       .Where(f => f is not null)
                       .OrderBy(f => f)
                       .ToList()
            : new List<string?>();

        // Update on the UI thread if a dispatcher is available
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher != null && !dispatcher.CheckAccess())
        {
            dispatcher.Invoke(() => SyncList(files!));
        }
        else
        {
            SyncList(files!);
        }

        FilesChanged?.Invoke();
    }

    private void SyncList(IList<string> files)
    {
        FileNames.Clear();
        foreach (var f in files) FileNames.Add(f);
    }

    private void SetupWatcher(string folderPath)
    {
        _watcher?.Dispose();
        if (!Directory.Exists(folderPath)) return;

        _watcher = new FileSystemWatcher(folderPath, "*.pdf")
        {
            NotifyFilter = NotifyFilters.FileName,
            EnableRaisingEvents = true
        };
        _watcher.Created += (_, _) => Refresh();
        _watcher.Deleted += (_, _) => Refresh();
        _watcher.Renamed += (_, _) => Refresh();
    }

    public void Dispose() => _watcher?.Dispose();

    // ── Metadata ──────────────────────────────────────────────────────────────

    /// Returns filename + last-modified (UTC ISO 8601) for each PDF in the folder.
    public IReadOnlyList<PdfFileMeta> GetFileMeta()
    {
        if (string.IsNullOrEmpty(_folder) || !Directory.Exists(_folder))
            return Array.Empty<PdfFileMeta>();

        return Directory.GetFiles(_folder, "*.pdf", SearchOption.TopDirectoryOnly)
            .Select(f => new FileInfo(f))
            .Where(fi => fi.Exists)
            .OrderBy(fi => fi.Name, StringComparer.OrdinalIgnoreCase)
            .Select(fi => new PdfFileMeta(fi.Name, fi.LastWriteTimeUtc.ToString("o")))
            .ToList();
    }
}

/// <summary>Filename + UTC last-modified timestamp for a single PDF.</summary>
public sealed record PdfFileMeta(string Name, string Modified);
