using System.Windows;
using System.Windows.Controls;
using CTHub.Models;

namespace CTHub;

public partial class BarcodeLinkPickerDialog : Window
{
    private readonly HubServer _hub;
    private readonly string    _barcodeValue;
    private readonly string    _sourceColumnId;
    private readonly string    _sourceTableName;

    private List<PickerRow> _allRows = [];
    private List<PickerRow> _filtered = [];

    private static readonly (string TableName, string Badge, string Label)[] Tables =
    [
        ("chasetactical",   "CT", "Chase Tactical"),
        ("toughhooks",      "TH", "Tough Hook"),
        ("shippingsupplys", "SS", "Shipping Supplies"),
    ];

    public BarcodeLinkPickerDialog(
        Window owner,
        HubServer hub,
        string barcodeValue,
        string sourceColumnId,
        string sourceTableName)
    {
        InitializeComponent();
        Owner = owner;

        _hub             = hub;
        _barcodeValue    = barcodeValue;
        _sourceColumnId  = sourceColumnId;
        _sourceTableName = sourceTableName;

        // Populate table filter
        TableFilter.Items.Add("All tables");
        foreach (var (_, _, label) in Tables)
            TableFilter.Items.Add(label);
        TableFilter.SelectedIndex = 0;

        BuildAllRows();
        ApplyFilter();

        Loaded += (_, _) => SearchBox.Focus();
    }

    // ── Data ──────────────────────────────────────────────────────────────────

    private void BuildAllRows()
    {
        // Collect IDs already linked to this barcode+column so we can exclude them
        var alreadyLinked = _hub.BarcodeLinks.GetAll()
            .Where(l => l.SourceBarcodeValue.Equals(_barcodeValue, StringComparison.OrdinalIgnoreCase)
                     && l.SourceColumnId == _sourceColumnId)
            .Select(l => l.TargetTableName + "|" + l.TargetEntryId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        _allRows = [];

        foreach (var ct in _hub.ChaseTactical.Items)
        {
            if (alreadyLinked.Contains($"chasetactical|{ct.Id}")) continue;
            var label = BuildLabelChaseTactical(ct);
            _allRows.Add(new PickerRow("chasetactical", "CT", ct.Id, label,
                $"{ct.ClassId}  ·  {ct.Bin}"));
        }

        foreach (var th in _hub.ToughHooks.Items)
        {
            if (alreadyLinked.Contains($"toughhooks|{th.Id}")) continue;
            var label = BuildLabelToughHook(th);
            _allRows.Add(new PickerRow("toughhooks", "TH", th.Id, label,
                $"{th.Sku}  ·  Bin {th.Bin}"));
        }

        foreach (var ss in _hub.ShippingSupplys.Items)
        {
            if (alreadyLinked.Contains($"shippingsupplys|{ss.Id}")) continue;
            _allRows.Add(new PickerRow("shippingsupplys", "SS", ss.Id,
                string.IsNullOrWhiteSpace(ss.Dimensions) ? ss.Id : ss.Dimensions,
                $"Bundle {ss.Bundle}  ·  Single {ss.Single}"));
        }
    }

    private static string BuildLabelChaseTactical(ChaseTacticalEntry ct)
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(ct.Bin))   parts.Add(ct.Bin);
        if (!string.IsNullOrWhiteSpace(ct.Label))  parts.Add(ct.Label);
        return parts.Count > 0 ? string.Join(" — ", parts) : ct.Id;
    }

    private static string BuildLabelToughHook(ToughHookEntry th)
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(th.Bin))         parts.Add(th.Bin);
        if (!string.IsNullOrWhiteSpace(th.Description)) parts.Add(th.Description);
        return parts.Count > 0 ? string.Join(" — ", parts) : th.Id;
    }

    // ── Filtering ─────────────────────────────────────────────────────────────

    private void ApplyFilter()
    {
        var search = SearchBox.Text.Trim();
        var tableIdx = TableFilter.SelectedIndex; // 0 = All

        _filtered = _allRows
            .Where(r =>
            {
                if (tableIdx > 0)
                {
                    var (tableName, _, _) = Tables[tableIdx - 1];
                    if (!r.TableName.Equals(tableName, StringComparison.OrdinalIgnoreCase))
                        return false;
                }

                if (!string.IsNullOrEmpty(search))
                {
                    var combined = $"{r.Label} {r.SubLabel}";
                    if (!combined.Contains(search, StringComparison.OrdinalIgnoreCase))
                        return false;
                }

                return true;
            })
            .OrderBy(r => r.TableName)
            .ThenBy(r => r.Label)
            .ToList();

        ResultsList.ItemsSource = _filtered;
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => ApplyFilter();
    private void TableFilter_SelectionChanged(object sender, SelectionChangedEventArgs e) => ApplyFilter();

    private void ResultsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        => LinkButton.IsEnabled = ResultsList.SelectedItem is PickerRow;

    private void ResultsList_DoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (ResultsList.SelectedItem is PickerRow)
            CommitLink();
    }

    // ── Commit ────────────────────────────────────────────────────────────────

    private void Link_Click(object sender, RoutedEventArgs e) => CommitLink();

    private void CommitLink()
    {
        if (ResultsList.SelectedItem is not PickerRow row) return;

        var entry = new BarcodeLinkEntry
        {
            Id                      = Guid.NewGuid().ToString(),
            SourceBarcodeValue      = _barcodeValue,
            SourceColumnId          = _sourceColumnId,
            SourceTableName         = _sourceTableName,
            TargetTableName         = row.TableName,
            TargetEntryId           = row.EntryId,
            TargetEntryLabelSnapshot = row.Label,
            CreatedAtUtc            = DateTime.UtcNow.ToString("o")
        };

        _ = _hub.BarcodeLinks.UpsertAsync(entry);
        DialogResult = true;
    }

    // ── View model ────────────────────────────────────────────────────────────

    private sealed record PickerRow(
        string TableName,
        string TableBadge,
        string EntryId,
        string Label,
        string SubLabel);
}
