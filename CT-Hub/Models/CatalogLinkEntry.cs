using System.Text.Json.Serialization;

namespace CTHub.Models;

public class CatalogLinkEntry
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("sourceCatalog")]
    public string SourceCatalog { get; set; } = string.Empty;

    [JsonPropertyName("sourceItemId")]
    public string SourceItemId { get; set; } = string.Empty;

    [JsonPropertyName("sourceItemLabelSnapshot")]
    public string SourceItemLabelSnapshot { get; set; } = string.Empty;

    [JsonPropertyName("scannedCode")]
    public string ScannedCode { get; set; } = string.Empty;

    [JsonPropertyName("linkCode")]
    public string LinkCode { get; set; } = string.Empty;

    [JsonPropertyName("createdAtUtc")]
    public string CreatedAtUtc { get; set; } = DateTime.UtcNow.ToString("o");
}
