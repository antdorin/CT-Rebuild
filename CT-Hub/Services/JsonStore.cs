using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace CTHub.Services;

/// <summary>
/// Thread-safe, JSON-on-disk store for a single collection.
/// Writes are atomic (write to .tmp then File.Replace).
/// Exposes an ObservableCollection for WPF data binding.
/// </summary>
public sealed class JsonStore<T> where T : class
{
    private readonly string _filePath;
    private readonly Func<T, string> _getId;
    private readonly WebSocketManager _ws;
    private readonly string _collectionName;
    private readonly object _lock = new();

    private static readonly JsonSerializerOptions _opts = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public ObservableCollection<T> Items { get; } = [];

    public JsonStore(string filePath, Func<T, string> getId, WebSocketManager ws, string collectionName)
    {
        _filePath = filePath;
        _getId = getId;
        _ws = ws;
        _collectionName = collectionName;

        Directory.CreateDirectory(Path.GetDirectoryName(filePath)!);
        Load();
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    public IReadOnlyList<T> GetAll()
    {
        lock (_lock) return Items.ToList();
    }

    // ── Write ─────────────────────────────────────────────────────────────────

    public async Task UpsertAsync(T item)
    {
        lock (_lock)
        {
            var id = _getId(item);
            var existing = Items.FirstOrDefault(x => _getId(x) == id);
            if (existing is not null)
                Items[Items.IndexOf(existing)] = item;
            else
                Items.Add(item);

            Persist();
        }

        await _ws.BroadcastAsync(new { type = "upsert", collection = _collectionName, data = item });
    }

    public async Task InsertAtAsync(T item, int index)
    {
        lock (_lock)
        {
            var id = _getId(item);
            var existing = Items.FirstOrDefault(x => _getId(x) == id);
            if (existing is not null)
                Items[Items.IndexOf(existing)] = item;
            else
            {
                var clamped = Math.Clamp(index, 0, Items.Count);
                Items.Insert(clamped, item);
            }
            Persist();
        }

        await _ws.BroadcastAsync(new { type = "upsert", collection = _collectionName, data = item });
    }

    public async Task DeleteAsync(string id)
    {
        T? removed = null;
        lock (_lock)
        {
            var item = Items.FirstOrDefault(x => _getId(x) == id);
            if (item is null) return;
            Items.Remove(item);
            removed = item;
            Persist();
        }

        await _ws.BroadcastAsync(new { type = "delete", collection = _collectionName, id });
    }

    // ── Persistence ────────────────────────────────────────────────────────────

    private void Load()
    {
        if (!File.Exists(_filePath)) return;
        try
        {
            var json = File.ReadAllText(_filePath);
            var list = JsonSerializer.Deserialize<List<T>>(json, _opts);
            if (list is null) return;
            foreach (var item in list) Items.Add(item);
        }
        catch
        {
            // Corrupt file — start empty, original preserved until next write
        }
    }

    /// <summary>Atomic write: serialise to .tmp then replace original.</summary>
    private void Persist()
    {
        try
        {
            var tmp = _filePath + ".tmp";
            var json = JsonSerializer.Serialize(Items.ToList(), _opts);
            File.WriteAllText(tmp, json);
            File.Move(tmp, _filePath, overwrite: true);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[JsonStore] Persist failed for {_collectionName}: {ex.Message}");
        }
    }
}
