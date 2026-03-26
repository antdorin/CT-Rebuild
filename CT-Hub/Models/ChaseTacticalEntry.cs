using System.Text.Json.Serialization;

namespace CTHub.Models;

public class ChaseTacticalEntry
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("bin")]
    public string Bin { get; set; } = string.Empty;

    [JsonPropertyName("className")]
    public string ClassName { get; set; } = string.Empty;

    [JsonPropertyName("classLetter")]
    public string ClassLetter { get; set; } = string.Empty;

    [JsonPropertyName("class")]
    public string ClassId { get; set; } = string.Empty;

    [JsonPropertyName("label")]
    public string Label { get; set; } = string.Empty;

    [JsonPropertyName("qty")]
    public int Qty { get; set; } = 0;

    [JsonPropertyName("notes")]
    public string Notes { get; set; } = string.Empty;
}
