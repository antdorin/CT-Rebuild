using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace CTHub.Models;

public class ToughHookEntry : INotifyPropertyChanged
{
    private string _id = Guid.NewGuid().ToString();
    private string _bin = string.Empty;
    private string _sku = string.Empty;
    private string _description = string.Empty;
    private int _qty;
    private int _stockThreshold;

    [JsonPropertyName("id")]
    public string Id
    {
        get => _id;
        set => SetField(ref _id, value);
    }

    [JsonPropertyName("bin")]
    public string Bin
    {
        get => _bin;
        set => SetField(ref _bin, value);
    }

    [JsonPropertyName("sku")]
    public string Sku
    {
        get => _sku;
        set => SetField(ref _sku, value);
    }

    [JsonPropertyName("description")]
    public string Description
    {
        get => _description;
        set => SetField(ref _description, value);
    }

    [JsonPropertyName("qty")]
    public int Qty
    {
        get => _qty;
        set => SetField(ref _qty, value);
    }

    [JsonPropertyName("stockThreshold")]
    public int StockThreshold
    {
        get => _stockThreshold;
        set => SetField(ref _stockThreshold, value);
    }

    private string _sectionLabel = string.Empty;

    [JsonPropertyName("sectionLabel")]
    public string SectionLabel
    {
        get => _sectionLabel;
        set => SetField(ref _sectionLabel, value);
    }

    [JsonPropertyName("extraFields")]
    public Dictionary<string, string> ExtraFields { get; set; } = new();

    /// <summary>Indexer for WPF dynamic column binding: {Binding [columnId]}</summary>
    public string this[string key]
    {
        get => ExtraFields.TryGetValue(key, out var v) ? v : string.Empty;
        set
        {
            if (ExtraFields.TryGetValue(key, out var cur) && cur == value) return;
            ExtraFields[key] = value;
            OnPropertyChanged($"Item[{key}]");
            OnPropertyChanged(string.Empty); // refresh MultiBinding (computed columns)
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
            return false;
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }
}
