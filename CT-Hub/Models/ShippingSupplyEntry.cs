using System.Text.Json.Serialization;

namespace CTHub.Models;

public class ShippingSupplyEntry
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("dimensions")]
    public string Dimensions { get; set; } = string.Empty;

    [JsonPropertyName("bundle")]
    public int Bundle { get; set; } = 0;

    [JsonPropertyName("single")]
    public int Single { get; set; } = 0;

    [JsonPropertyName("stockThreshold")]
    public int StockThreshold { get; set; } = 0;
}