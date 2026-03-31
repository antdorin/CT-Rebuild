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
