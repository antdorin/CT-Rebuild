using System.Text.Json.Serialization;

namespace CTHub.Models;

public enum DataKind
{
    Text,
    Number,
    Dropdown,
    Date,
    BarcodeScan,
    Photo,
    Gps,
    ManualEntry,
    Toggle,
    Computed
}

public class ColumnDefinition
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("tableName")]
    public string TableName { get; set; } = string.Empty;

    [JsonPropertyName("headerText")]
    public string HeaderText { get; set; } = string.Empty;

    [JsonPropertyName("dataKind")]
    public DataKind DataKind { get; set; } = DataKind.Text;

    [JsonPropertyName("sortOrder")]
    public int SortOrder { get; set; } = 0;

    [JsonPropertyName("createdAtUtc")]
    public string CreatedAtUtc { get; set; } = DateTime.UtcNow.ToString("o");

    /// <summary>
    /// Selectable values when DataKind is Dropdown.
    /// </summary>
    [JsonPropertyName("options")]
    public List<string>? Options { get; set; }

    /// <summary>
    /// Typed model property path (e.g. "Bin", "Qty") for seeded columns.
    /// Null/empty = extra field, bound via indexer [Id].
    /// </summary>
    [JsonPropertyName("bindingPath")]
    public string? BindingPath { get; set; }

    /// <summary>If true the column is read-only in the grid.</summary>
    [JsonPropertyName("isReadOnly")]
    public bool IsReadOnly { get; set; }

    /// <summary>
    /// Preferred column width in pixels. 0 = default (140 px). -1 = star (fill remaining).
    /// </summary>
    [JsonPropertyName("defaultWidth")]
    public double DefaultWidth { get; set; }

    /// <summary>If true the column is the collapsible ID column (grey, small font, pinned last).</summary>
    [JsonPropertyName("isCollapsibleId")]
    public bool IsCollapsibleId { get; set; }

    /// <summary>
    /// Signed column-ID formula for Computed columns. Format: "+colId1 +colId2 -colId3".
    /// </summary>
    [JsonPropertyName("formula")]
    public string? Formula { get; set; }

    /// <summary>Column-level warning threshold for Number columns. Cells at/below this value are highlighted red; within 25% above are highlighted amber.</summary>
    [JsonPropertyName("warningThreshold")]
    public double? WarningThreshold { get; set; }
}
