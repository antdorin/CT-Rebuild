using System.Text.Json.Serialization;

namespace CTHub.Models;

public class BarcodeLinkEntry
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    /// <summary>The barcode / QR value stored in the source cell.</summary>
    [JsonPropertyName("sourceBarcodeValue")]
    public string SourceBarcodeValue { get; set; } = string.Empty;

    /// <summary>The ColumnDefinition ID of the BarcodeScan column that owns the cell.</summary>
    [JsonPropertyName("sourceColumnId")]
    public string SourceColumnId { get; set; } = string.Empty;

    /// <summary>Table the source row belongs to (e.g. "chasetactical").</summary>
    [JsonPropertyName("sourceTableName")]
    public string SourceTableName { get; set; } = string.Empty;

    /// <summary>Table the linked row belongs to.</summary>
    [JsonPropertyName("targetTableName")]
    public string TargetTableName { get; set; } = string.Empty;

    /// <summary>Row ID of the linked entry.</summary>
    [JsonPropertyName("targetEntryId")]
    public string TargetEntryId { get; set; } = string.Empty;

    /// <summary>Human-readable label copied at link time so the record stays intelligible even if the target row is later renamed.</summary>
    [JsonPropertyName("targetEntryLabelSnapshot")]
    public string TargetEntryLabelSnapshot { get; set; } = string.Empty;

    [JsonPropertyName("createdAtUtc")]
    public string CreatedAtUtc { get; set; } = DateTime.UtcNow.ToString("o");
}
