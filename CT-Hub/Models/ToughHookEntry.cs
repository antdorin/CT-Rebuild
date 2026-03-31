using System.Text.Json.Serialization;

namespace CTHub.Models;

public class ToughHookEntry
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("bin")]
    public string Bin { get; set; } = string.Empty;

    [JsonPropertyName("sku")]
    public string Sku { get; set; } = string.Empty;

    [JsonPropertyName("description")]
    public string Description { get; set; } = string.Empty;

    [JsonPropertyName("qty")]
    public int Qty { get; set; } = 0;

    [JsonPropertyName("stockThreshold")]
    public int StockThreshold { get; set; } = 0;
}
