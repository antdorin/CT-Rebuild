using System.Text.Json.Serialization;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace CTHub.Models;

public class ChaseTacticalEntry : INotifyPropertyChanged
{
    private string _id = Guid.NewGuid().ToString();
    private string _bin = string.Empty;
    private string _className = string.Empty;
    private string _classLetter = string.Empty;
    private string _classId = string.Empty;
    private string _label = string.Empty;
    private int _qty;
    private int _stockThreshold;
    private string _notes = string.Empty;

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

    [JsonPropertyName("className")]
    public string ClassName
    {
        get => _className;
        set => SetField(ref _className, value);
    }

    [JsonPropertyName("classLetter")]
    public string ClassLetter
    {
        get => _classLetter;
        set => SetField(ref _classLetter, value);
    }

    [JsonPropertyName("class")]
    public string ClassId
    {
        get => _classId;
        set => SetField(ref _classId, value);
    }

    [JsonPropertyName("label")]
    public string Label
    {
        get => _label;
        set => SetField(ref _label, value);
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

    [JsonPropertyName("notes")]
    public string Notes
    {
        get => _notes;
        set => SetField(ref _notes, value);
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
