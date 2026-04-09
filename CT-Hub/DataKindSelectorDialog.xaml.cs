using System.Windows;
using System.Windows.Controls.Primitives;
using CTHub.Models;

namespace CTHub;

public partial class DataKindSelectorDialog : Window
{
    public string ResultHeaderText { get; private set; } = string.Empty;
    public DataKind ResultDataKind { get; private set; } = DataKind.Text;
    public List<string>? ResultOptions { get; private set; }
    public string? ResultFormula { get; private set; }

    private readonly List<ToggleButton> _kindButtons;
    private readonly IReadOnlyList<CTHub.Models.ColumnDefinition> _availableColumns;

    private sealed record ColOption(string Id, string HeaderText)
    {
        public override string ToString() => HeaderText;
    }

    public DataKindSelectorDialog(Window owner, string initialHeader = "", DataKind initialKind = DataKind.Text, List<string>? initialOptions = null, string? initialFormula = null, IReadOnlyList<CTHub.Models.ColumnDefinition>? availableColumns = null)
    {
        InitializeComponent();
        Owner = owner;

        _availableColumns = availableColumns ?? [];
        _kindButtons =
        [
            KindText, KindNumber, KindDropdown, KindDate, KindToggle,
            KindBarcode, KindPhoto, KindGps, KindManual, KindComputed
        ];

        var colOptions = _availableColumns
            .Where(c => c.DataKind != DataKind.Computed && !c.IsCollapsibleId)
            .Select(c => new ColOption(c.Id, c.HeaderText))
            .ToList();
        FormulaCol1.ItemsSource = colOptions;
        FormulaCol2.ItemsSource = colOptions;
        FormulaSign2.ItemsSource = new[] { "+", "-" };
        FormulaSign2.SelectedIndex = 0;

        HeaderTextBox.Text = initialHeader;
        SelectKind(initialKind);

        if (initialOptions is not null)
            DropdownOptionsBox.Text = string.Join(", ", initialOptions);

        if (!string.IsNullOrEmpty(initialFormula))
        {
            var parts = initialFormula.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 1)
            {
                var (id1, mult1) = ParseTerm(parts[0]);
                FormulaCol1.SelectedItem        = colOptions.FirstOrDefault(c => c.Id == id1);
                FormulaMultiplier1.Text         = mult1.ToString("G", System.Globalization.CultureInfo.InvariantCulture);
            }
            if (parts.Length >= 2)
            {
                var sign = parts[1][0].ToString();
                var (id2, mult2) = ParseTerm(parts[1]);
                FormulaSign2.SelectedItem       = sign;
                FormulaCol2.SelectedItem        = colOptions.FirstOrDefault(c => c.Id == id2);
                FormulaMultiplier2.Text         = mult2.ToString("G", System.Globalization.CultureInfo.InvariantCulture);
            }
        }

        Loaded += (_, _) => { HeaderTextBox.Focus(); HeaderTextBox.SelectAll(); };
    }

    private void SelectKind(DataKind kind)
    {
        foreach (var btn in _kindButtons)
            btn.IsChecked = false;

        var target = _kindButtons.FirstOrDefault(b => b.Tag?.ToString() == kind.ToString());
        if (target is not null) target.IsChecked = true;

        DropdownOptionsPanel.Visibility = kind == DataKind.Dropdown ? Visibility.Visible : Visibility.Collapsed;
        ComputedFormulaPanel.Visibility = kind == DataKind.Computed ? Visibility.Visible : Visibility.Collapsed;
    }

    private void KindButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not ToggleButton clicked) return;

        // Enforce single-select
        foreach (var btn in _kindButtons)
            btn.IsChecked = btn == clicked;

        DropdownOptionsPanel.Visibility = clicked.Tag?.ToString() == "Dropdown" ? Visibility.Visible : Visibility.Collapsed;
        ComputedFormulaPanel.Visibility = clicked.Tag?.ToString() == "Computed" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        var header = HeaderTextBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(header))
        {
            MessageBox.Show("Please enter a column name.", "CT Hub", MessageBoxButton.OK, MessageBoxImage.Information);
            HeaderTextBox.Focus();
            return;
        }

        var selectedBtn = _kindButtons.FirstOrDefault(b => b.IsChecked == true);
        if (selectedBtn is null)
        {
            MessageBox.Show("Please select a data type.", "CT Hub", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        if (!Enum.TryParse<DataKind>(selectedBtn.Tag?.ToString(), out var kind))
            kind = DataKind.Text;

        if (kind == DataKind.Computed)
        {
            if (FormulaCol1.SelectedItem is not ColOption op1 || FormulaCol2.SelectedItem is not ColOption op2)
            {
                MessageBox.Show("Please select both formula columns.", "CT Hub", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            var sign  = FormulaSign2.SelectedItem?.ToString() ?? "+";
            var mult1 = ParseMultiplierInput(FormulaMultiplier1.Text, "Column A multiplier");
            var mult2 = ParseMultiplierInput(FormulaMultiplier2.Text, "Column B multiplier");
            if (mult1 is null || mult2 is null) return;
            ResultFormula = $"+{op1.Id}*{mult1.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)} {sign}{op2.Id}*{mult2.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)}";
        }
        else
        {
            ResultFormula = null;
        }

        ResultHeaderText = header;
        ResultDataKind   = kind;
        ResultOptions    = kind == DataKind.Dropdown
            ? DropdownOptionsBox.Text
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .ToList()
            : null;

        DialogResult = true;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
        => DialogResult = false;

    /// <summary>Parses a formula term like "+colId*24" or "+colId" into (colId, multiplier).</summary>
    private static (string ColId, double Multiplier) ParseTerm(string term)
    {
        var rest    = term.TrimStart('+', '-');
        var starIdx = rest.IndexOf('*');
        if (starIdx < 0) return (rest, 1.0);
        var colId = rest[..starIdx];
        double.TryParse(rest[(starIdx + 1)..],
            System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out var mult);
        return (colId, mult == 0 ? 1.0 : mult);
    }

    /// <summary>Validates a user-entered multiplier string; shows a dialog and returns null on failure.</summary>
    private double? ParseMultiplierInput(string text, string fieldName)
    {
        if (double.TryParse(text.Trim(),
            System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out var v) && v != 0)
            return v;
        MessageBox.Show($"{fieldName} must be a non-zero number.", "CT Hub",
            MessageBoxButton.OK, MessageBoxImage.Information);
        return null;
    }
}
