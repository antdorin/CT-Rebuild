using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Text;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Text.Json;
using System.Net.Http;
using CTHub.Models;
using CTHub.Services;
using Microsoft.Win32;

namespace CTHub;

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private readonly HubServer _hub = App.Hub;
    private readonly CdpDevToolsService _cdp = new();
    private readonly AppSettings _settings = AppSettings.Instance;
    private ICollectionView? _chaseView;
    private ICollectionView? _toughHooksView;
    private ICollectionView? _shippingSupplysView;
    private ICollectionView? _qrMappingsView;
    private ICollectionView? _pdfFilesView;
    private DataGridColumnHeader? _activeHeader;
    private DataGrid? _activeGrid;
    private readonly List<string> _devCdpRawEvents = [];
    private readonly HashSet<char> _devHotkeyBuffer = [];
    private DateTime _devHotkeyLastInputUtc = DateTime.MinValue;
    private bool _isDevToolsVisible = true;

    // ── Bindable properties ───────────────────────────────────────────────────

    public System.Collections.ObjectModel.ObservableCollection<ChaseTacticalEntry> ChaseTacticalItems
        => _hub.ChaseTactical.Items;

    public static readonly List<string> BinLocations = new()
    {
        "1-A-1A","1-A-1B","1-A-1C","1-A-1D","1-A-1E","1-A-1F",
        "1-A-2A","1-A-2B","1-A-2C","1-A-2D","1-A-2E","1-A-2F",
        "1-A-3A","1-A-3B","1-A-3C","1-A-3D","1-A-3E","1-A-3F",
        "1-A-4A","1-A-4B","1-A-4C","1-A-4D","1-A-4E","1-A-4F",
        "1-B-1A","1-B-1B","1-B-1C","1-B-1D","1-B-1E","1-B-1F",
        "1-B-2A","1-B-2B","1-B-2C","1-B-2D","1-B-2E","1-B-2F",
        "1-B-3A","1-B-3B","1-B-3C","1-B-3D","1-B-3E","1-B-3F",
        "1-B-4A","1-B-4B","1-B-4C","1-B-4D","1-B-4E","1-B-4F",
        "1-B-5A","1-B-5B","1-B-5C","1-B-5D","1-B-5E","1-B-5F",
        "1-B-6A","1-B-6B","1-B-6C","1-B-6D","1-B-6E","1-B-6F",
        "2-A-1A","2-A-1B","2-A-1C","2-A-1D","2-A-1E","2-A-1F",
        "2-A-2A","2-A-2B","2-A-2C","2-A-2D","2-A-2E","2-A-2F",
        "2-A-3A","2-A-3B","2-A-3C","2-A-3D","2-A-3E","2-A-3F",
        "2-A-4A","2-A-4B","2-A-4C","2-A-4D","2-A-4E","2-A-4F",
        "2-B-1A","2-B-1B","2-B-1C","2-B-1D","2-B-1E","2-B-1F",
        "2-B-2A","2-B-2B","2-B-2C","2-B-2D","2-B-2E","2-B-2F",
        "2-B-3A","2-B-3B","2-B-3C","2-B-3D","2-B-3E","2-B-3F",
        "2-B-4A","2-B-4B","2-B-4C","2-B-4D","2-B-4E","2-B-4F",
        "2-B-5A","2-B-5B","2-B-5C","2-B-5D","2-B-5E","2-B-5F",
        "2-B-6A","2-B-6B","2-B-6C","2-B-6D","2-B-6E","2-B-6F",
        "3-A-1A","3-A-1B","3-A-1C","3-A-1D","3-A-1E","3-A-1F",
        "3-A-2A","3-A-2B","3-A-2C","3-A-2D","3-A-2E","3-A-2F",
        "3-A-3A","3-A-3B","3-A-3C","3-A-3D","3-A-3E","3-A-3F",
        "3-A-4A","3-A-4B","3-A-4C","3-A-4D","3-A-4E","3-A-4F",
        "3-B-1A","3-B-1B","3-B-1C","3-B-1D","3-B-1E","3-B-1F",
        "3-B-2A","3-B-2B","3-B-2C","3-B-2D","3-B-2E","3-B-2F",
        "3-B-3A","3-B-3B","3-B-3C","3-B-3D","3-B-3E","3-B-3F",
        "3-B-4A","3-B-4B","3-B-4C","3-B-4D","3-B-4E","3-B-4F",
        "3-B-5A","3-B-5B","3-B-5C","3-B-5D","3-B-5E","3-B-5F",
        "3-B-6A","3-B-6B","3-B-6C","3-B-6D","3-B-6E","3-B-6F",
    };

    public static readonly List<string> ClassNames = new()
    {
        "AMMO POUCHES",
        "MEDICAL",
        "PLATE CARRIER ACCESSORY",
        "GLOVES",
        "BELTS & PERSONAL LANYARDS",
        "GP POUCHES",
        "SOFT ARMOR",
        "VEST ACCESSORY",
        "HARD ARMOR",
        "PLATE CARRIER",
        "ACTIVE SHOOTER KIT",
        "RADIO POUCHES",
    };

    public static readonly List<string> ClassLetters = Enumerable
        .Range('A', 26)
        .Select(c => ((char)c).ToString())
        .ToList();

    public System.Collections.ObjectModel.ObservableCollection<ToughHookEntry> ToughHookItems
        => _hub.ToughHooks.Items;

    public System.Collections.ObjectModel.ObservableCollection<ShippingSupplyEntry> ShippingSupplysItems
        => _hub.ShippingSupplys.Items;

    public System.Collections.ObjectModel.ObservableCollection<QrClassMapping> QrMappingItems
        => _hub.QrMappings.Items;

    public System.Collections.ObjectModel.ObservableCollection<PdfFileRow> PdfFileRows
        => _hub.PdfFolder.FileRows;

    private string _chaseSearchText = string.Empty;
    public string ChaseSearchText
    {
        get => _chaseSearchText;
        set
        {
            if (_chaseSearchText == value) return;
            _chaseSearchText = value;
            OnPropertyChanged();
            _chaseView?.Refresh();
        }
    }

    private string _toughHooksSearchText = string.Empty;
    public string ToughHooksSearchText
    {
        get => _toughHooksSearchText;
        set
        {
            if (_toughHooksSearchText == value) return;
            _toughHooksSearchText = value;
            OnPropertyChanged();
            _toughHooksView?.Refresh();
        }
    }

    private string _qrMappingsSearchText = string.Empty;
    public string QrMappingsSearchText
    {
        get => _qrMappingsSearchText;
        set
        {
            if (_qrMappingsSearchText == value) return;
            _qrMappingsSearchText = value;
            OnPropertyChanged();
            _qrMappingsView?.Refresh();
        }
    }

    private string _shippingSupplysSearchText = string.Empty;
    public string ShippingSupplysSearchText
    {
        get => _shippingSupplysSearchText;
        set
        {
            if (_shippingSupplysSearchText == value) return;
            _shippingSupplysSearchText = value;
            OnPropertyChanged();
            _shippingSupplysView?.Refresh();
        }
    }

    private string _pdfSearchText = string.Empty;
    public string PdfSearchText
    {
        get => _pdfSearchText;
        set
        {
            if (_pdfSearchText == value) return;
            _pdfSearchText = value;
            OnPropertyChanged();
            _pdfFilesView?.Refresh();
        }
    }

    private string _statusText = $"http://localhost:{HubServer.Port}";
    public string StatusText
    {
        get => _statusText;
        set
        {
            _statusText = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(StatusTextDisplay));
        }
    }

    public string StatusTextDisplay => IsPrivacyModeOn ? MaskSensitive(StatusText) : StatusText;

    private string _clientCountText = "0 connected";
    public string ClientCountText
    {
        get => _clientCountText;
        set { _clientCountText = value; OnPropertyChanged(); }
    }

    private string _lastBroadcast = "No broadcasts yet";
    public string LastBroadcast
    {
        get => _lastBroadcast;
        set { _lastBroadcast = value; OnPropertyChanged(); }
    }

    private string _lastConnectedDevice = "No devices yet";
    public string LastConnectedDevice
    {
        get => _lastConnectedDevice;
        set
        {
            _lastConnectedDevice = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(LastConnectedDeviceDisplay));
        }
    }

    public string LastConnectedDeviceDisplay => IsPrivacyModeOn ? MaskSensitive(LastConnectedDevice) : LastConnectedDevice;

    private bool _isBroadcastingNow;
    public bool IsBroadcastingNow
    {
        get => _isBroadcastingNow;
        set
        {
            _isBroadcastingNow = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(BroadcastDotColor));
            OnPropertyChanged(nameof(BroadcastTextColor));
        }
    }

    private static readonly Brush _dotGreen  = Freeze(new SolidColorBrush(Color.FromRgb(0x4E, 0xC9, 0xA0)));
    private static readonly Brush _dotGray   = Freeze(new SolidColorBrush(Color.FromRgb(0x3C, 0x3C, 0x3C)));
    private static readonly Brush _textMuted = Freeze(new SolidColorBrush(Color.FromRgb(0x85, 0x85, 0x85)));
    private static Brush Freeze(Brush b) { b.Freeze(); return b; }

    public Brush BroadcastDotColor  => IsBroadcastingNow ? _dotGreen : _dotGray;
    public Brush BroadcastTextColor => IsBroadcastingNow ? _dotGreen : _textMuted;

    private string _broadcastStatusText = "Off";
    public string BroadcastStatusText
    {
        get => _broadcastStatusText;
        set { _broadcastStatusText = value; OnPropertyChanged(); }
    }

    private string _broadcastButtonText = "\u25b6  Start Broadcasting";
    public string BroadcastButtonText
    {
        get => _broadcastButtonText;
        set { _broadcastButtonText = value; OnPropertyChanged(); }
    }

    private string _lastBeaconText = "No beacons sent yet";
    public string LastBeaconText
    {
        get => _lastBeaconText;
        set { _lastBeaconText = value; OnPropertyChanged(); }
    }

    private string _localAddresses = "Scanning...";
    public string LocalAddresses
    {
        get => _localAddresses;
        set
        {
            _localAddresses = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(LocalAddressesDisplay));
        }
    }

    public string LocalAddressesDisplay => IsPrivacyModeOn ? MaskSensitive(LocalAddresses) : LocalAddresses;

    private string _hubUrl = "Scanning...";
    public string HubUrl
    {
        get => _hubUrl;
        set
        {
            _hubUrl = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(HubUrlDisplay));
        }
    }

    public string HubUrlDisplay => IsPrivacyModeOn ? MaskSensitive(HubUrl) : HubUrl;
    public string HttpPortDisplay => IsPrivacyModeOn ? "xxxx" : "5050";
    public string BeaconDestinationDisplay => IsPrivacyModeOn ? "xxx.xxx.xxx.xxx : UDP xxxx" : "255.255.255.255 : UDP 5051";

    private string _devChromeEndpoint = "http://127.0.0.1:9222";
    public string DevChromeEndpoint
    {
        get => _devChromeEndpoint;
        set
        {
            _devChromeEndpoint = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(DevChromeEndpointMasked));
            SaveDevToolSettings();
        }
    }

    public string DevChromeEndpointMasked => MaskSensitive(DevChromeEndpoint);

    public Visibility EndpointEditorVisibility => IsPrivacyModeOn ? Visibility.Collapsed : Visibility.Visible;
    public Visibility EndpointMaskedVisibility => IsPrivacyModeOn ? Visibility.Visible : Visibility.Collapsed;

    private bool _isPrivacyModeOn;
    public bool IsPrivacyModeOn
    {
        get => _isPrivacyModeOn;
        set
        {
            _isPrivacyModeOn = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(StatusTextDisplay));
            OnPropertyChanged(nameof(LastConnectedDeviceDisplay));
            OnPropertyChanged(nameof(LocalAddressesDisplay));
            OnPropertyChanged(nameof(HubUrlDisplay));
            OnPropertyChanged(nameof(HttpPortDisplay));
            OnPropertyChanged(nameof(BeaconDestinationDisplay));
            OnPropertyChanged(nameof(DevChromeEndpointMasked));
            OnPropertyChanged(nameof(EndpointEditorVisibility));
            OnPropertyChanged(nameof(EndpointMaskedVisibility));
            OnPropertyChanged(nameof(DevCdpStatusDisplay));
            RebuildDevCdpEventDisplay();
        }
    }

    public List<string> DevBrowserOptions { get; } = ["Chrome", "Edge", "Custom"];

    private string _devBrowserKind = "Chrome";
    public string DevBrowserKind
    {
        get => _devBrowserKind;
        set
        {
            _devBrowserKind = NormalizeBrowserKind(value);
            OnPropertyChanged();
            SaveDevToolSettings();
        }
    }

    private string _devBrowserExecutablePath = string.Empty;
    public string DevBrowserExecutablePath
    {
        get => _devBrowserExecutablePath;
        set
        {
            _devBrowserExecutablePath = value;
            OnPropertyChanged();
            SaveDevToolSettings();
        }
    }

    private bool _devUseLocalBrowserData;
    public bool DevUseLocalBrowserData
    {
        get => _devUseLocalBrowserData;
        set
        {
            _devUseLocalBrowserData = value;
            OnPropertyChanged();
            SaveDevToolSettings();
        }
    }

    private string _devBrowserUserDataDir = string.Empty;
    public string DevBrowserUserDataDir
    {
        get => _devBrowserUserDataDir;
        set
        {
            _devBrowserUserDataDir = value;
            OnPropertyChanged();
            SaveDevToolSettings();
        }
    }

    private string _devBrowserProfileDirectory = "Default";
    public string DevBrowserProfileDirectory
    {
        get => _devBrowserProfileDirectory;
        set
        {
            _devBrowserProfileDirectory = value;
            OnPropertyChanged();
            SaveDevToolSettings();
        }
    }

    private bool _devAutoConnectFirstTab = true;
    public bool DevAutoConnectFirstTab
    {
        get => _devAutoConnectFirstTab;
        set
        {
            _devAutoConnectFirstTab = value;
            OnPropertyChanged();
            SaveDevToolSettings();
        }
    }

    private bool _devUseDirectLocalProfile;
    public bool DevUseDirectLocalProfile
    {
        get => _devUseDirectLocalProfile;
        set
        {
            _devUseDirectLocalProfile = value;
            OnPropertyChanged();
            SaveDevToolSettings();
        }
    }

    private string _devCdpStatus = "Disconnected";
    public string DevCdpStatus
    {
        get => _devCdpStatus;
        set
        {
            _devCdpStatus = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(DevCdpStatusDisplay));
        }
    }

    public string DevCdpStatusDisplay => IsPrivacyModeOn ? MaskSensitive(DevCdpStatus) : DevCdpStatus;

    public System.Collections.ObjectModel.ObservableCollection<CdpTarget> DevCdpTabs { get; } = [];
    public System.Collections.ObjectModel.ObservableCollection<string> DevCdpEvents { get; } = [];
    public System.Collections.ObjectModel.ObservableCollection<string> DevDetectedBrowserProfiles { get; } = [];

    private CdpTarget? _devSelectedCdpTab;
    public CdpTarget? DevSelectedCdpTab
    {
        get => _devSelectedCdpTab;
        set { _devSelectedCdpTab = value; OnPropertyChanged(); }
    }

    // ── Constructor ───────────────────────────────────────────────────────────

    public MainWindow()
    {
        InitializeComponent();

        _devChromeEndpoint = string.IsNullOrWhiteSpace(_settings.DevChromeEndpoint)
            ? "http://127.0.0.1:9222"
            : _settings.DevChromeEndpoint;
        _devBrowserKind = NormalizeBrowserKind(_settings.DevBrowserKind);
        _devBrowserExecutablePath = _settings.DevBrowserExecutablePath ?? string.Empty;
        _devUseLocalBrowserData = _settings.DevUseLocalBrowserData;
        _devBrowserUserDataDir = _settings.DevBrowserUserDataDir ?? string.Empty;
        _devBrowserProfileDirectory = string.IsNullOrWhiteSpace(_settings.DevBrowserProfileDirectory)
            ? "Default"
            : _settings.DevBrowserProfileDirectory;
        _devAutoConnectFirstTab = _settings.DevAutoConnectFirstTab;
        _devUseDirectLocalProfile = !_settings.DevUseProfileSnapshot;

        DetectProfilesInCurrentUserDataDir(selectDefaultIfMissing: false);

        DataContext = this;
        PreviewKeyDown += MainWindow_PreviewKeyDown;
        UpdateDevToolsVisibility();

        _cdp.Log += msg => Dispatcher.InvokeAsync(() => AddDevCdpLog(msg));
        _cdp.NetworkEventReceived += evt => Dispatcher.InvokeAsync(() =>
        {
            var line = $"NET {evt.Status} {evt.Url}";
            AddDevCdpLog(line);
        });

        // Refresh client count and beacon timestamp every 2 s
        var timer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(2)
        };
        timer.Tick += (_, _) =>
        {
            var n = _hub.WsManager.ConnectedCount;
            ClientCountText = n == 1 ? "1 client connected" : $"{n} clients connected";
            if (_hub.LastBeaconTime.HasValue)
                LastBeaconText = $"Last beacon sent: {_hub.LastBeaconTime.Value:HH:mm:ss}";
        };
        timer.Start();

        // Notify when a device connects
        _hub.ClientConnected += ip => Dispatcher.InvokeAsync(() =>
        {
            LastConnectedDevice = $"{ip}  \u00b7  {DateTime.Now:HH:mm:ss}";
            StatusText = $"Device connected: {ip}";
            var restore = $"http://localhost:{HubServer.Port}";
            var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            t.Tick += (_, _) => { StatusText = restore; t.Stop(); };
            t.Start();
        });

        // Sync broadcast state to UI
        _hub.BroadcastStateChanged += isOn => Dispatcher.InvokeAsync(() =>
        {
            IsBroadcastingNow   = isOn;
            BroadcastStatusText = isOn ? "Broadcasting" : "Off";
            BroadcastButtonText = isOn ? "\u25a0  Stop Broadcasting" : "\u25b6  Start Broadcasting";
        });

        // Load PDF folder and bind list
        PdfFileGrid.ItemsSource = PdfFileRows;
        if (!string.IsNullOrEmpty(_hub.PdfFolder.CurrentFolder))
            PdfFolderPathText.Text = _hub.PdfFolder.CurrentFolder;

        InitializeSearchFilters();
        UpdatePdfEditorModeUi();

        // Populate server info panel
        RefreshServerInfo();
    }

    protected override async void OnClosed(EventArgs e)
    {
        await _cdp.DisposeAsync();
        base.OnClosed(e);
    }

    // Updates the last-broadcast timestamp shown in the status bar.
    private void Touch() => LastBroadcast = $"Last write: {DateTime.Now:HH:mm:ss}";

    private void AddDevCdpLog(string line)
    {
        var stamped = $"{DateTime.Now:HH:mm:ss}  {line}";
        _devCdpRawEvents.Insert(0, stamped);
        while (_devCdpRawEvents.Count > 500)
            _devCdpRawEvents.RemoveAt(_devCdpRawEvents.Count - 1);
        RebuildDevCdpEventDisplay();
    }

    private void RebuildDevCdpEventDisplay()
    {
        DevCdpEvents.Clear();
        foreach (var raw in _devCdpRawEvents)
            DevCdpEvents.Add(IsPrivacyModeOn ? MaskSensitive(raw) : raw);
    }

    private static string MaskSensitive(string? text)
    {
        if (string.IsNullOrEmpty(text))
            return string.Empty;

        var sb = new StringBuilder(text.Length);
        foreach (var ch in text)
            sb.Append(char.IsDigit(ch) ? 'x' : ch);
        return sb.ToString();
    }

    private void MainWindow_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        char? pressed = KeyToUpperChar(e.Key);
        if (pressed is null)
            return;

        if (DateTime.UtcNow - _devHotkeyLastInputUtc > TimeSpan.FromSeconds(5))
            _devHotkeyBuffer.Clear();

        _devHotkeyLastInputUtc = DateTime.UtcNow;

        char c = pressed.Value;
        if (c is 'C' or 'H' or 'A' or 'D')
        {
            _devHotkeyBuffer.Add(c);
            if (_devHotkeyBuffer.Count == 4)
            {
                _devHotkeyBuffer.Clear();
                _isDevToolsVisible = !_isDevToolsVisible;
                UpdateDevToolsVisibility();
                AddDevCdpLog(_isDevToolsVisible ? "Dev Tools tab revealed via CHAD combo." : "Dev Tools tab hidden via CHAD combo.");
            }
        }
    }

    private static char? KeyToUpperChar(Key key)
    {
        if (key >= Key.A && key <= Key.Z)
            return (char)('A' + (key - Key.A));
        return null;
    }

    private void UpdateDevToolsVisibility()
    {
        if (DevToolsTab is null)
            return;

        DevToolsTab.Visibility = _isDevToolsVisible ? Visibility.Visible : Visibility.Collapsed;
        if (!_isDevToolsVisible && DevToolsTab.IsSelected && DevToolsTab.Parent is TabControl tc)
            tc.SelectedIndex = 0;
    }

    private void InitializeSearchFilters()
    {
        _chaseView = CollectionViewSource.GetDefaultView(ChaseTacticalItems);
        _chaseView.Filter = item => FilterChase(item as ChaseTacticalEntry);

        _toughHooksView = CollectionViewSource.GetDefaultView(ToughHookItems);
        _toughHooksView.Filter = item => FilterToughHook(item as ToughHookEntry);

        _shippingSupplysView = CollectionViewSource.GetDefaultView(ShippingSupplysItems);
        _shippingSupplysView.Filter = item => FilterShippingSupplys(item as ShippingSupplyEntry);

        _qrMappingsView = CollectionViewSource.GetDefaultView(QrMappingItems);
        _qrMappingsView.Filter = item => FilterQrMapping(item as QrClassMapping);

        _pdfFilesView = CollectionViewSource.GetDefaultView(PdfFileRows);
        _pdfFilesView.Filter = item => FilterPdfRow(item as PdfFileRow);
    }

    private bool ContainsText(string? source, string term)
        => !string.IsNullOrEmpty(source) && source.Contains(term, StringComparison.OrdinalIgnoreCase);

    private bool FilterChase(ChaseTacticalEntry? entry)
    {
        if (entry is null) return false;
        var term = ChaseSearchText.Trim();
        if (term.Length == 0) return true;

        return ContainsText(entry.Bin, term)
            || ContainsText(entry.ClassName, term)
            || ContainsText(entry.ClassLetter, term)
            || ContainsText(entry.ClassId, term)
            || ContainsText(entry.Label, term)
            || ContainsText(entry.Notes, term)
            || ContainsText(entry.Id, term)
            || entry.Qty.ToString().Contains(term, StringComparison.OrdinalIgnoreCase);
    }

    private static string BuildClassId(ChaseTacticalEntry entry)
    {
        if (string.IsNullOrWhiteSpace(entry.ClassLetter))
            return string.Empty;

        var letter = entry.ClassLetter.Trim().ToUpperInvariant();
        var number = Random.Shared.Next(0, 1001);
        return $"{letter}-{number:D3}";
    }

    private static bool IsChaseClassFieldColumn(DataGridColumn column)
    {
        if (column is DataGridComboBoxColumn combo)
        {
            if (combo.SelectedItemBinding is Binding selectedBinding)
            {
                var path = selectedBinding.Path?.Path;
                return string.Equals(path, nameof(ChaseTacticalEntry.ClassName), StringComparison.Ordinal)
                    || string.Equals(path, nameof(ChaseTacticalEntry.ClassLetter), StringComparison.Ordinal);
            }
        }

        if (column is DataGridBoundColumn bound && bound.Binding is Binding binding)
        {
            var path = binding.Path?.Path;
            return string.Equals(path, nameof(ChaseTacticalEntry.ClassName), StringComparison.Ordinal)
                || string.Equals(path, nameof(ChaseTacticalEntry.ClassLetter), StringComparison.Ordinal);
        }

        return false;
    }

    private bool FilterToughHook(ToughHookEntry? entry)
    {
        if (entry is null) return false;
        var term = ToughHooksSearchText.Trim();
        if (term.Length == 0) return true;

        return ContainsText(entry.Bin, term)
            || ContainsText(entry.Sku, term)
            || ContainsText(entry.Description, term)
            || ContainsText(entry.Id, term)
            || entry.Qty.ToString().Contains(term, StringComparison.OrdinalIgnoreCase);
    }

    private bool FilterQrMapping(QrClassMapping? entry)
    {
        if (entry is null) return false;
        var term = QrMappingsSearchText.Trim();
        if (term.Length == 0) return true;

        return ContainsText(entry.QrValue, term)
            || ContainsText(entry.Classification, term)
            || ContainsText(entry.Description, term)
            || ContainsText(entry.Id, term);
    }

    private bool FilterShippingSupplys(ShippingSupplyEntry? entry)
    {
        if (entry is null) return false;
        var term = ShippingSupplysSearchText.Trim();
        if (term.Length == 0) return true;

        return ContainsText(entry.Dimensions, term)
            || entry.Bundle.ToString().Contains(term, StringComparison.OrdinalIgnoreCase)
            || entry.Single.ToString().Contains(term, StringComparison.OrdinalIgnoreCase)
            || ContainsText(entry.Id, term);
    }

    private bool FilterPdfRow(PdfFileRow? row)
    {
        var term = PdfSearchText.Trim();
        if (term.Length == 0) return true;
        if (row is null) return false;

        return ContainsText(row.Name, term)
            || ContainsText(row.SalesOrders, term)
            || row.ImportDateTime.ToString("yyyy-MM-dd HH:mm:ss").Contains(term, StringComparison.OrdinalIgnoreCase);
    }

    // ── Column header context menu handlers ──────────────────────────────────

    private void ColumnHeader_ContextMenuOpening(object sender, ContextMenuEventArgs e)
    {
        if (sender is not DataGridColumnHeader header)
            return;

        _activeHeader = header;
        _activeGrid = FindParentDataGrid(header);

        if (header.ContextMenu is null)
        {
            var menu = new ContextMenu();

            var editItem = new MenuItem { Header = "Edit Header" };
            editItem.Click += ColumnHeader_Edit_Click;

            var addItem = new MenuItem { Header = "Add Header (after)" };
            addItem.Click += ColumnHeader_Add_Click;

            var deleteItem = new MenuItem { Header = "Delete Header" };
            deleteItem.Click += ColumnHeader_Delete_Click;

            menu.Items.Add(editItem);
            menu.Items.Add(addItem);
            menu.Items.Add(deleteItem);

            header.ContextMenu = menu;
        }
    }

    private void ColumnHeader_Edit_Click(object sender, RoutedEventArgs e)
    {
        if (_activeHeader?.Column is null)
            return;

        var currentHeader = _activeHeader.Column.Header?.ToString() ?? string.Empty;
        var updatedHeader = PromptForText("Edit Header", "Header text:", currentHeader);

        if (string.IsNullOrWhiteSpace(updatedHeader))
            return;

        _activeHeader.Column.Header = updatedHeader.Trim();
    }

    private void ColumnHeader_Add_Click(object sender, RoutedEventArgs e)
    {
        if (_activeGrid is null || _activeHeader?.Column is null)
            return;

        var header = PromptForText("Add Header", "New header text:", "New Column");
        if (string.IsNullOrWhiteSpace(header))
            return;

        var insertIndex = _activeGrid.Columns.IndexOf(_activeHeader.Column) + 1;
        var placeholderColumn = new DataGridTextColumn
        {
            Header = header.Trim(),
            Binding = new Binding { Source = string.Empty },
            Width = new DataGridLength(140),
            IsReadOnly = true
        };

        _activeGrid.Columns.Insert(insertIndex, placeholderColumn);
    }

    private void ColumnHeader_Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_activeGrid is null || _activeHeader?.Column is null)
            return;

        if (_activeGrid.Columns.Count <= 1)
            return;

        _activeGrid.Columns.Remove(_activeHeader.Column);
    }

    private static DataGrid? FindParentDataGrid(DependencyObject start)
    {
        var current = start;
        while (current is not null)
        {
            if (current is DataGrid grid)
                return grid;

            current = VisualTreeHelper.GetParent(current);
        }

        return null;
    }

    private string? PromptForText(string title, string prompt, string initialValue)
    {
        var input = new TextBox
        {
            Text = initialValue,
            MinWidth = 280,
            Margin = new Thickness(0, 8, 0, 12)
        };

        var okButton = new Button
        {
            Content = "OK",
            Width = 80,
            Margin = new Thickness(0, 0, 8, 0),
            IsDefault = true
        };

        var cancelButton = new Button
        {
            Content = "Cancel",
            Width = 80,
            IsCancel = true
        };

        var dialog = new Window
        {
            Title = title,
            Owner = this,
            ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false,
            SizeToContent = SizeToContent.WidthAndHeight,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            WindowStyle = WindowStyle.ToolWindow,
            Content = new StackPanel
            {
                Margin = new Thickness(16),
                Children =
                {
                    new TextBlock { Text = prompt },
                    input,
                    new StackPanel
                    {
                        Orientation = Orientation.Horizontal,
                        HorizontalAlignment = HorizontalAlignment.Right,
                        Children = { okButton, cancelButton }
                    }
                }
            }
        };

        okButton.Click += (_, _) => dialog.DialogResult = true;

        return dialog.ShowDialog() == true ? input.Text : null;
    }

    private string? PromptForMultilineText(string title, string prompt)
    {
        var promptText = new TextBlock
        {
            Text = prompt,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 8)
        };

        var input = new TextBox
        {
            Width = 700,
            Height = 380,
            TextWrapping = TextWrapping.Wrap,
            AcceptsReturn = true,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            Margin = new Thickness(0, 0, 0, 12)
        };

        var okButton = new Button
        {
            Content = "OK",
            Width = 80,
            Margin = new Thickness(0, 0, 8, 0),
            IsDefault = true
        };

        var cancelButton = new Button
        {
            Content = "Cancel",
            Width = 80,
            IsCancel = true
        };

        var dialog = new Window
        {
            Title = title,
            Owner = this,
            ResizeMode = ResizeMode.CanResize,
            ShowInTaskbar = false,
            Width = 760,
            Height = 540,
            MinWidth = 620,
            MinHeight = 420,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            WindowStyle = WindowStyle.ToolWindow,
            Content = new Grid
            {
                Margin = new Thickness(16),
                RowDefinitions =
                {
                    new RowDefinition { Height = GridLength.Auto },
                    new RowDefinition { Height = new GridLength(1, GridUnitType.Star) },
                    new RowDefinition { Height = GridLength.Auto }
                }
            }
        };

        Grid.SetRow(promptText, 0);
        Grid.SetRow(input, 1);
        var buttonsPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Children = { okButton, cancelButton }
        };
        Grid.SetRow(buttonsPanel, 2);

        var rootGrid = (Grid)dialog.Content;
        rootGrid.Children.Add(promptText);
        rootGrid.Children.Add(input);
        rootGrid.Children.Add(buttonsPanel);

        okButton.Click += (_, _) => dialog.DialogResult = true;

        return dialog.ShowDialog() == true ? input.Text : null;
    }

    private string? AcquireChaseBulkImportText()
    {
        var sourceChoice = MessageBox.Show(
            "Choose import source for Chase Tactical TSV.\n\nYes = Load from file\nNo = Paste text\nCancel = Abort",
            "Import Bulk",
            MessageBoxButton.YesNoCancel,
            MessageBoxImage.Question);

        if (sourceChoice == MessageBoxResult.Cancel)
            return null;

        if (sourceChoice == MessageBoxResult.Yes)
        {
            var dialog = new OpenFileDialog
            {
                Title = "Select Chase Tactical import text",
                Filter = "Text/CSV files|*.txt;*.csv|All files|*.*",
                Multiselect = false
            };

            if (dialog.ShowDialog() != true)
                return null;

            return File.ReadAllText(dialog.FileName);
        }

        return PromptForMultilineText(
            "Paste Chase Tactical TSV",
            "Paste tab-separated rows in Label<TAB>Qty<TAB>Bin format.");
    }

    private static string BuildChaseDuplicateKey(ChaseTacticalEntry entry)
        => $"{entry.Bin.Trim().ToUpperInvariant()}|{entry.Label.Trim()}";

    private static void AppendUnknownQtyNote(ChaseTacticalEntry entry)
    {
        if (entry.Notes.Contains("Qty ?", StringComparison.OrdinalIgnoreCase))
            return;

        entry.Notes = string.IsNullOrWhiteSpace(entry.Notes)
            ? "Qty ?"
            : $"{entry.Notes.Trim()} | Qty ?";
    }

    private string? AcquireToughHooksBulkImportText()
    {
        var sourceChoice = MessageBox.Show(
            "Choose import source for Tough Hooks.\n\nYes = Load from file\nNo = Paste text\nCancel = Abort",
            "Import Bulk",
            MessageBoxButton.YesNoCancel,
            MessageBoxImage.Question);

        if (sourceChoice == MessageBoxResult.Cancel)
            return null;

        if (sourceChoice == MessageBoxResult.Yes)
        {
            var dialog = new OpenFileDialog
            {
                Title = "Select Tough Hooks import text",
                Filter = "Text/CSV files|*.txt;*.csv|All files|*.*",
                Multiselect = false
            };

            if (dialog.ShowDialog() != true)
                return null;

            return File.ReadAllText(dialog.FileName);
        }

        return PromptForMultilineText(
            "Paste Tough Hooks import text",
            "Accepted formats: Description/Qty/Bin/SKU rows, or two blocks of Description lines then SKU lines.");
    }

    private static string BuildToughHookDuplicateKey(ToughHookEntry entry)
        => entry.Sku.Trim().ToUpperInvariant();
    // ── Chase Tactical handlers ───────────────────────────────────────────────

    private void ChaseTactical_Add(object sender, RoutedEventArgs e)
    {
        var entry = new ChaseTacticalEntry
        {
            Bin = "—",
            ClassName = ClassNames[0],
            ClassLetter = "A",
            Label = "New item"
        };
        entry.ClassId = BuildClassId(entry);
        _ = _hub.ChaseTactical.UpsertAsync(entry);
        Touch();
        ChaseTacticalGrid.ScrollIntoView(entry);
    }

    private void ChaseTactical_Delete(object sender, RoutedEventArgs e)
    {
        var selected = ChaseTacticalGrid.SelectedItems
            .Cast<ChaseTacticalEntry>()
            .ToList();

        foreach (var item in selected)
        {
            _ = _hub.ChaseTactical.DeleteAsync(item.Id);
        }

        if (selected.Count > 0) Touch();
    }

    private async void ChaseTactical_ImportBulk(object sender, RoutedEventArgs e)
    {
        var importText = AcquireChaseBulkImportText();
        if (string.IsNullOrWhiteSpace(importText))
            return;

        var parseResult = TextImportParser.ParseChaseTacticalTsv(importText);
        if (parseResult.Rows.Count == 0)
        {
            var errorPreview = parseResult.Errors.Count == 0
                ? "No importable rows were found."
                : string.Join(Environment.NewLine, parseResult.Errors.Take(8));

            MessageBox.Show(
                $"Import aborted.\n\n{errorPreview}",
                "Import Bulk",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        var existingKeys = new HashSet<string>(
            _hub.ChaseTactical.Items.Select(BuildChaseDuplicateKey),
            StringComparer.OrdinalIgnoreCase);

        var incomingKeyCounts = parseResult.Rows
            .GroupBy(r => BuildChaseDuplicateKey(r.Entry), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.Count(), StringComparer.OrdinalIgnoreCase);

        var duplicateAgainstExisting = parseResult.Rows.Count(r => existingKeys.Contains(BuildChaseDuplicateKey(r.Entry)));
        var duplicateWithinImport = incomingKeyCounts.Values.Sum(c => Math.Max(0, c - 1));
        var unknownQtyCount = parseResult.Rows.Count(r => r.HadUnknownQty);

        var rowsToImport = parseResult.Rows;
        if (duplicateAgainstExisting > 0 || duplicateWithinImport > 0)
        {
            var duplicateChoice = MessageBox.Show(
                $"Duplicates detected.\n\nAgainst existing rows: {duplicateAgainstExisting}\nWithin import text: {duplicateWithinImport}\n\nYes = Keep duplicates\nNo = Remove duplicates\nCancel = Abort",
                "Resolve Duplicates",
                MessageBoxButton.YesNoCancel,
                MessageBoxImage.Warning);

            if (duplicateChoice == MessageBoxResult.Cancel)
                return;

            if (duplicateChoice == MessageBoxResult.No)
            {
                var seenIncoming = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                rowsToImport = parseResult.Rows
                    .Where(row =>
                    {
                        var key = BuildChaseDuplicateKey(row.Entry);
                        if (existingKeys.Contains(key))
                            return false;

                        return seenIncoming.Add(key);
                    })
                    .ToList();
            }
        }

        if (rowsToImport.Count == 0)
        {
            MessageBox.Show(
                "All parsed rows were filtered out by duplicate rules.",
                "Import Bulk",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        foreach (var row in rowsToImport)
        {
            var entry = row.Entry;
            if (row.HadUnknownQty)
                AppendUnknownQtyNote(entry);

            if (string.IsNullOrWhiteSpace(entry.ClassId) && !string.IsNullOrWhiteSpace(entry.ClassLetter))
                entry.ClassId = BuildClassId(entry);

            await _hub.ChaseTactical.UpsertAsync(entry);
        }

        Touch();

        var summaryBuilder = new StringBuilder();
        summaryBuilder.AppendLine($"Imported: {rowsToImport.Count}");
        summaryBuilder.AppendLine($"Unknown qty mapped to Qty=0: {unknownQtyCount}");
        summaryBuilder.AppendLine($"Parse errors: {parseResult.Errors.Count}");

        if (parseResult.Errors.Count > 0)
        {
            summaryBuilder.AppendLine();
            summaryBuilder.AppendLine("Sample errors:");
            foreach (var err in parseResult.Errors.Take(6))
                summaryBuilder.AppendLine($"- {err}");
        }

        MessageBox.Show(
            summaryBuilder.ToString(),
            "Import Complete",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void ChaseTactical_CellEditEnding(object sender, DataGridCellEditEndingEventArgs e)
    {
        if (e.EditAction == DataGridEditAction.Commit &&
            e.Row.Item is ChaseTacticalEntry item)
        {
            var regenerateClassId = IsChaseClassFieldColumn(e.Column)
                || string.IsNullOrWhiteSpace(item.ClassId);

            // Let the DataGrid commit the binding first, then persist
            Dispatcher.InvokeAsync(() =>
            {
                if (regenerateClassId)
                    item.ClassId = BuildClassId(item);
                _ = _hub.ChaseTactical.UpsertAsync(item);
                Touch();
            });
        }
    }

    // ── Tough Hooks handlers ──────────────────────────────────────────────────

    private void ToughHooks_Add(object sender, RoutedEventArgs e)
    {
        var entry = new ToughHookEntry { Bin = "—", Sku = "NEW" };
        _ = _hub.ToughHooks.UpsertAsync(entry);
        Touch();
        ToughHooksGrid.ScrollIntoView(entry);
    }

    private void ToughHooks_Delete(object sender, RoutedEventArgs e)
    {
        var selected = ToughHooksGrid.SelectedItems
            .Cast<ToughHookEntry>()
            .ToList();

        foreach (var item in selected)
        {
            _ = _hub.ToughHooks.DeleteAsync(item.Id);
        }

        if (selected.Count > 0) Touch();
    }

    private async void ToughHooks_ImportBulk(object sender, RoutedEventArgs e)
    {
        var importText = AcquireToughHooksBulkImportText();
        if (string.IsNullOrWhiteSpace(importText))
            return;

        var parseResult = TextImportParser.ParseToughHooks(importText);
        if (parseResult.Rows.Count == 0)
        {
            var errorPreview = parseResult.Errors.Count == 0
                ? "No importable rows were found."
                : string.Join(Environment.NewLine, parseResult.Errors.Take(8));

            MessageBox.Show(
                $"Import aborted.\n\n{errorPreview}",
                "Import Bulk",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        var existingKeys = new HashSet<string>(
            _hub.ToughHooks.Items.Select(BuildToughHookDuplicateKey),
            StringComparer.OrdinalIgnoreCase);

        var incomingKeyCounts = parseResult.Rows
            .GroupBy(r => BuildToughHookDuplicateKey(r.Entry), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.Count(), StringComparer.OrdinalIgnoreCase);

        var duplicateAgainstExisting = parseResult.Rows.Count(r => existingKeys.Contains(BuildToughHookDuplicateKey(r.Entry)));
        var duplicateWithinImport = incomingKeyCounts.Values.Sum(c => Math.Max(0, c - 1));

        var rowsToImport = parseResult.Rows;
        if (duplicateAgainstExisting > 0 || duplicateWithinImport > 0)
        {
            var duplicateChoice = MessageBox.Show(
                $"Duplicates detected by SKU.\n\nAgainst existing rows: {duplicateAgainstExisting}\nWithin import text: {duplicateWithinImport}\n\nYes = Keep duplicates\nNo = Remove duplicates\nCancel = Abort",
                "Resolve Duplicates",
                MessageBoxButton.YesNoCancel,
                MessageBoxImage.Warning);

            if (duplicateChoice == MessageBoxResult.Cancel)
                return;

            if (duplicateChoice == MessageBoxResult.No)
            {
                var seenIncoming = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                rowsToImport = parseResult.Rows
                    .Where(row =>
                    {
                        var key = BuildToughHookDuplicateKey(row.Entry);
                        if (string.IsNullOrWhiteSpace(key) || existingKeys.Contains(key))
                            return false;

                        return seenIncoming.Add(key);
                    })
                    .ToList();
            }
        }

        if (rowsToImport.Count == 0)
        {
            MessageBox.Show(
                "All parsed rows were filtered out by duplicate rules.",
                "Import Bulk",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        foreach (var row in rowsToImport)
            await _hub.ToughHooks.UpsertAsync(row.Entry);

        Touch();

        var summaryBuilder = new StringBuilder();
        summaryBuilder.AppendLine($"Imported: {rowsToImport.Count}");
        summaryBuilder.AppendLine($"Parse errors: {parseResult.Errors.Count}");

        if (parseResult.Errors.Count > 0)
        {
            summaryBuilder.AppendLine();
            summaryBuilder.AppendLine("Sample errors:");
            foreach (var err in parseResult.Errors.Take(6))
                summaryBuilder.AppendLine($"- {err}");
        }

        MessageBox.Show(
            summaryBuilder.ToString(),
            "Import Complete",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void ToughHooks_CellEditEnding(object sender, DataGridCellEditEndingEventArgs e)
    {
        if (e.EditAction == DataGridEditAction.Commit &&
            e.Row.Item is ToughHookEntry item)
        {
            Dispatcher.InvokeAsync(() =>
            {
                _ = _hub.ToughHooks.UpsertAsync(item);
                Touch();
            });
        }
    }

    // ── QR Mappings handlers ──────────────────────────────────────────────────

    private void QrMappings_Add(object sender, RoutedEventArgs e)
    {
        var entry = new QrClassMapping { QrValue = "SCAN_ME", Classification = "Unclassified" };
        _ = _hub.QrMappings.UpsertAsync(entry);
        Touch();
        QrMappingsGrid.ScrollIntoView(entry);
    }

    private void QrMappings_Delete(object sender, RoutedEventArgs e)
    {
        var selected = QrMappingsGrid.SelectedItems
            .Cast<QrClassMapping>()
            .ToList();

        foreach (var item in selected)
        {
            _ = _hub.QrMappings.DeleteAsync(item.Id);
        }

        if (selected.Count > 0) Touch();
    }

    private void QrMappings_CellEditEnding(object sender, DataGridCellEditEndingEventArgs e)
    {
        if (e.EditAction == DataGridEditAction.Commit &&
            e.Row.Item is QrClassMapping item)
        {
            Dispatcher.InvokeAsync(() =>
            {
                _ = _hub.QrMappings.UpsertAsync(item);
                Touch();
            });
        }
    }

    // ── Shipping Supplys handlers ─────────────────────────────────────────────

    private void ShippingSupplys_Add(object sender, RoutedEventArgs e)
    {
        var entry = new ShippingSupplyEntry { Dimensions = "New box", Bundle = 0, Single = 0 };
        _ = _hub.ShippingSupplys.UpsertAsync(entry);
        Touch();
        ShippingSupplysGrid.ScrollIntoView(entry);
    }

    private void ShippingSupplys_Delete(object sender, RoutedEventArgs e)
    {
        var selected = ShippingSupplysGrid.SelectedItems
            .Cast<ShippingSupplyEntry>()
            .ToList();

        foreach (var item in selected)
        {
            _ = _hub.ShippingSupplys.DeleteAsync(item.Id);
        }

        if (selected.Count > 0) Touch();
    }

    private void ShippingSupplys_CellEditEnding(object sender, DataGridCellEditEndingEventArgs e)
    {
        if (e.EditAction == DataGridEditAction.Commit &&
            e.Row.Item is ShippingSupplyEntry item)
        {
            Dispatcher.InvokeAsync(() =>
            {
                _ = _hub.ShippingSupplys.UpsertAsync(item);
                Touch();
            });
        }
    }

    // ── Dev CDP handlers ─────────────────────────────────────────────────────

    private async void DevCdp_RefreshTabs(object sender, RoutedEventArgs e)
        => await ReloadDevCdpTabsAsync();

    private async Task ReloadDevCdpTabsAsync(bool autoConnect = false)
    {
        try
        {
            DevCdpStatus = "Loading Chrome tabs...";
            var tabs = await CdpDevToolsService.GetTargetsAsync(DevChromeEndpoint);

            DevCdpTabs.Clear();
            foreach (var tab in tabs)
                DevCdpTabs.Add(tab);

            DevSelectedCdpTab = DevCdpTabs.FirstOrDefault();
            DevCdpStatus = $"Tabs found: {DevCdpTabs.Count}";
            AddDevCdpLog($"Found {DevCdpTabs.Count} debuggable page tab(s).");

            if ((autoConnect || DevAutoConnectFirstTab) && DevSelectedCdpTab is not null)
            {
                await ConnectSelectedDevTabAsync();
            }
        }
        catch (Exception ex)
        {
            DevCdpStatus = "Tab discovery failed";
            AddDevCdpLog($"Tab discovery failed: {ex.Message}");
        }
    }

    private async void DevCdp_Connect(object sender, RoutedEventArgs e)
        => await ConnectSelectedDevTabAsync();

    private async Task ConnectSelectedDevTabAsync()
    {
        if (DevSelectedCdpTab is null)
        {
            AddDevCdpLog("Select a Chrome tab first.");
            return;
        }

        try
        {
            DevCdpStatus = "Connecting...";
            await _cdp.ConnectAsync(DevSelectedCdpTab.WebSocketDebuggerUrl);
            DevCdpStatus = $"Connected: {DevSelectedCdpTab.Title}";
            AddDevCdpLog($"Connected to: {DevSelectedCdpTab.Title}");
        }
        catch (Exception ex)
        {
            DevCdpStatus = "Connect failed";
            AddDevCdpLog($"Connect failed: {ex.Message}");
        }
    }

    private async void DevCdp_Disconnect(object sender, RoutedEventArgs e)
    {
        await _cdp.DisconnectAsync();
        DevCdpStatus = "Disconnected";
        AddDevCdpLog("Disconnected.");
    }

    private void DevCdp_ClearLog(object sender, RoutedEventArgs e)
    {
        _devCdpRawEvents.Clear();
        DevCdpEvents.Clear();
        AddDevCdpLog("Log cleared.");
    }

    private async void DevCdp_LaunchChrome(object sender, RoutedEventArgs e)
    {
        try
        {
            var browserExe = ResolveBrowserExecutablePath();
            if (string.IsNullOrWhiteSpace(browserExe))
            {
                MessageBox.Show(
                    "Selected browser executable could not be found. Use Browse... to set a valid path, or switch Browser to Chrome/Edge.",
                    "CT-Hub",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return;
            }

            string userDataDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CT-Hub",
                "dev-chrome-profile");

            string browserProcessName = GetBrowserProcessName();
            if (DevUseLocalBrowserData && !string.IsNullOrWhiteSpace(browserProcessName) && Process.GetProcessesByName(browserProcessName).Length > 0)
            {
                DevCdpStatus = "Close all browser windows, then launch again.";
                AddDevCdpLog($"{DevBrowserKind} is already running. Remote-debug flags are ignored when attaching to an existing process.");
                MessageBox.Show(
                    $"{DevBrowserKind} is already running.\n\nClose all {DevBrowserKind} windows first, then click Launch again.\nThis is required when using local browser data/profile.",
                    "CT-Hub",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
                return;
            }

            if (DevUseLocalBrowserData)
            {
                string sourceUserDataDir = DevBrowserUserDataDir?.Trim() ?? string.Empty;
                if (string.IsNullOrWhiteSpace(sourceUserDataDir) || !Directory.Exists(sourceUserDataDir))
                {
                    MessageBox.Show(
                        "Local user data directory is missing or invalid. Set User Data Dir or click Use Local Chrome Data.",
                        "CT-Hub",
                        MessageBoxButton.OK,
                        MessageBoxImage.Warning);
                    return;
                }

                string localProfileName = string.IsNullOrWhiteSpace(DevBrowserProfileDirectory)
                    ? "Default"
                    : DevBrowserProfileDirectory.Trim();

                if (DevUseDirectLocalProfile)
                {
                    userDataDir = sourceUserDataDir;
                    AddDevCdpLog("Using direct local profile mode.");
                }
                else
                {
                    DevCdpStatus = "Preparing local browser data snapshot...";
                    userDataDir = await PrepareSeededDebugUserDataAsync(sourceUserDataDir, localProfileName);
                }
            }
            else
            {
                Directory.CreateDirectory(userDataDir);
            }

            int debugPort = GetChromeDebugPort();
            string profileName = string.IsNullOrWhiteSpace(DevBrowserProfileDirectory)
                ? "Default"
                : DevBrowserProfileDirectory.Trim();

            var psi = new ProcessStartInfo
            {
                FileName = browserExe,
                Arguments = $"--remote-debugging-port={debugPort} --user-data-dir=\"{userDataDir}\" --profile-directory=\"{profileName}\"",
                UseShellExecute = true
            };

            Process.Start(psi);
            DevCdpStatus = $"Launched debug {DevBrowserKind} on port {debugPort}. Refreshing tabs...";
            AddDevCdpLog($"Launched {DevBrowserKind}: {browserExe}");
            AddDevCdpLog($"Using browser data: {userDataDir} / {profileName}");

            // Wait until endpoint is up, then refresh tabs.
            bool endpointUp = await WaitForDebugEndpointAsync(DevChromeEndpoint);
            if (!endpointUp)
            {
                DevCdpStatus = "Browser launched, but debug endpoint is not reachable.";
                AddDevCdpLog($"Endpoint did not open: {DevChromeEndpoint}");
                AddDevCdpLog("Tip: close all browser windows and relaunch from CT-Hub.");
                return;
            }

            await ReloadDevCdpTabsAsync(autoConnect: true);
        }
        catch (Exception ex)
        {
            DevCdpStatus = "Failed to launch debug Chrome";
            AddDevCdpLog($"Launch failed: {ex.Message}");
            MessageBox.Show(
                $"Could not launch Chrome. {ex.Message}",
                "CT-Hub",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private void DevCdp_BrowseBrowserExe(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "Select Browser Executable",
            Filter = "Executable (*.exe)|*.exe|All files (*.*)|*.*",
            CheckFileExists = true
        };

        if (dlg.ShowDialog(this) == true)
        {
            DevBrowserExecutablePath = dlg.FileName;
            if (!string.Equals(DevBrowserKind, "Custom", StringComparison.OrdinalIgnoreCase))
                DevBrowserKind = "Custom";
            AddDevCdpLog($"Custom browser set: {DevBrowserExecutablePath}");
        }
    }

    private void DevCdp_UseLocalChromeData(object sender, RoutedEventArgs e)
    {
        DevBrowserKind = "Chrome";
        DevUseLocalBrowserData = true;
        DevBrowserUserDataDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Google",
            "Chrome",
            "User Data");
        DevBrowserProfileDirectory = "Default";
        DetectProfilesInCurrentUserDataDir(selectDefaultIfMissing: true);
        AddDevCdpLog($"Local Chrome data selected: {DevBrowserUserDataDir}");
    }

    private void DevCdp_DetectProfiles(object sender, RoutedEventArgs e)
    {
        DetectProfilesInCurrentUserDataDir(selectDefaultIfMissing: true);
    }

    private void DetectProfilesInCurrentUserDataDir(bool selectDefaultIfMissing)
    {
        DevDetectedBrowserProfiles.Clear();

        string dir = DevBrowserUserDataDir?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir))
        {
            AddDevCdpLog("Profile detection skipped: User Data Dir is missing or invalid.");
            return;
        }

        var profiles = Directory.EnumerateDirectories(dir)
            .Select(Path.GetFileName)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Select(name => name!)
            .Where(name =>
                string.Equals(name, "Default", StringComparison.OrdinalIgnoreCase) ||
                name.StartsWith("Profile ", StringComparison.OrdinalIgnoreCase))
            .OrderBy(name => string.Equals(name, "Default", StringComparison.OrdinalIgnoreCase) ? 0 : 1)
            .ThenBy(name => name)
            .ToList();

        foreach (var profile in profiles)
            DevDetectedBrowserProfiles.Add(profile);

        if (selectDefaultIfMissing && DevDetectedBrowserProfiles.Count > 0)
        {
            bool currentExists = DevDetectedBrowserProfiles.Any(p =>
                string.Equals(p, DevBrowserProfileDirectory?.Trim(), StringComparison.OrdinalIgnoreCase));

            if (!currentExists)
                DevBrowserProfileDirectory = DevDetectedBrowserProfiles[0];
        }

        AddDevCdpLog($"Detected {DevDetectedBrowserProfiles.Count} profile(s): {string.Join(", ", DevDetectedBrowserProfiles)}");
    }

    private async Task<string> PrepareSeededDebugUserDataAsync(string sourceUserDataDir, string profileName)
    {
        string snapshotsRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CT-Hub",
            "dev-chrome-snapshots");

        Directory.CreateDirectory(snapshotsRoot);

        string targetUserDataDir = Path.Combine(
            snapshotsRoot,
            DateTime.Now.ToString("yyyyMMdd-HHmmss"));

        string sourceProfileDir = Path.Combine(sourceUserDataDir, profileName);
        if (!Directory.Exists(sourceProfileDir))
            throw new InvalidOperationException($"Profile directory not found: {sourceProfileDir}");

        AddDevCdpLog("Seeding debug profile from local browser data...");

        await Task.Run(() =>
        {
            Directory.CreateDirectory(targetUserDataDir);

            string sourceLocalState = Path.Combine(sourceUserDataDir, "Local State");
            if (File.Exists(sourceLocalState))
                File.Copy(sourceLocalState, Path.Combine(targetUserDataDir, "Local State"), overwrite: true);

            string targetProfileDir = Path.Combine(targetUserDataDir, profileName);
            CopyDirectoryRecursive(sourceProfileDir, targetProfileDir);
        });

        AddDevCdpLog($"Seeded snapshot: {targetUserDataDir}");
        return targetUserDataDir;
    }

    private static void CopyDirectoryRecursive(string sourceDir, string destinationDir)
    {
        Directory.CreateDirectory(destinationDir);

        foreach (var file in Directory.EnumerateFiles(sourceDir))
        {
            var name = Path.GetFileName(file);
            var destinationFile = Path.Combine(destinationDir, name);
            File.Copy(file, destinationFile, overwrite: true);
        }

        foreach (var directory in Directory.EnumerateDirectories(sourceDir))
        {
            var name = Path.GetFileName(directory);
            var childDestination = Path.Combine(destinationDir, name);
            CopyDirectoryRecursive(directory, childDestination);
        }
    }

    private string NormalizeBrowserKind(string? value)
    {
        if (string.Equals(value, "Edge", StringComparison.OrdinalIgnoreCase)) return "Edge";
        if (string.Equals(value, "Custom", StringComparison.OrdinalIgnoreCase)) return "Custom";
        return "Chrome";
    }

    private string? ResolveBrowserExecutablePath()
    {
        if (string.Equals(DevBrowserKind, "Custom", StringComparison.OrdinalIgnoreCase))
            return File.Exists(DevBrowserExecutablePath) ? DevBrowserExecutablePath : null;

        string[] paths = string.Equals(DevBrowserKind, "Edge", StringComparison.OrdinalIgnoreCase)
            ?
            [
                @"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
                @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
            ]
            :
            [
                @"C:\Program Files\Google\Chrome\Application\chrome.exe",
                @"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
            ];

        return paths.FirstOrDefault(File.Exists);
    }

    private int GetChromeDebugPort()
    {
        try
        {
            if (Uri.TryCreate(DevChromeEndpoint, UriKind.Absolute, out var uri) && uri.Port > 0)
                return uri.Port;
        }
        catch
        {
            // fall back to default below
        }

        return 9222;
    }

    private string GetBrowserProcessName()
    {
        if (string.Equals(DevBrowserKind, "Edge", StringComparison.OrdinalIgnoreCase))
            return "msedge";
        return "chrome";
    }

    private async Task<bool> WaitForDebugEndpointAsync(string endpoint, int attempts = 20, int delayMs = 300)
    {
        try
        {
            if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var uri))
                return false;

            string host = uri.Host;
            int port = uri.Port;

            for (int i = 0; i < attempts; i++)
            {
                try
                {
                    using var tcp = new TcpClient();
                    var connectTask = tcp.ConnectAsync(host, port);
                    var winner = await Task.WhenAny(connectTask, Task.Delay(250));
                    if (winner == connectTask && tcp.Connected)
                        return true;
                }
                catch
                {
                    // keep retrying
                }

                await Task.Delay(delayMs);
            }
        }
        catch
        {
            // treated as endpoint unavailable
        }

        return false;
    }

    private void SaveDevToolSettings()
    {
        _settings.DevChromeEndpoint = DevChromeEndpoint?.Trim() ?? "http://127.0.0.1:9222";
        _settings.DevBrowserKind = NormalizeBrowserKind(DevBrowserKind);
        _settings.DevBrowserExecutablePath = DevBrowserExecutablePath?.Trim() ?? string.Empty;
        _settings.DevUseLocalBrowserData = DevUseLocalBrowserData;
        _settings.DevBrowserUserDataDir = DevBrowserUserDataDir?.Trim() ?? string.Empty;
        _settings.DevBrowserProfileDirectory = DevBrowserProfileDirectory?.Trim() ?? "Default";
        _settings.DevAutoConnectFirstTab = DevAutoConnectFirstTab;
        _settings.DevUseProfileSnapshot = !DevUseDirectLocalProfile;
        _settings.Save();
    }

    // ── Broadcast toggle ──────────────────────────────────────────────────────

    private void Broadcast_Toggle(object sender, RoutedEventArgs e)
    {
        if (_hub.IsBroadcasting)
            _hub.StopBroadcast();
        else
            _hub.StartBroadcast();
    }

    // ── Server info ───────────────────────────────────────────────────────────

    private void RefreshServerInfo()
    {
        var ips = System.Net.NetworkInformation.NetworkInterface
            .GetAllNetworkInterfaces()
            .Where(ni =>
                ni.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up &&
                ni.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback)
            .SelectMany(ni => ni.GetIPProperties().UnicastAddresses)
            .Where(ua => ua.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
            .Select(ua => ua.Address.ToString())
            .ToList();

        LocalAddresses = ips.Count > 0 ? string.Join(",  ", ips) : "Not found";
        HubUrl = ips.Count > 0
            ? $"ws://{ips[0]}:{HubServer.Port}/ws"
            : $"ws://localhost:{HubServer.Port}/ws";
    }

    // ── INotifyPropertyChanged ────────────────────────────────────────────────

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    // ── PDF Folder handlers ───────────────────────────────────────────────────

    private void PdfFolder_Browse(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Select PDF folder",
            Multiselect = false
        };

        if (dialog.ShowDialog() == true)
        {
            var folder = dialog.FolderName;
            _hub.PdfFolder.SetFolder(folder);
            PdfFolderPathText.Text = folder;
            Touch();
        }
    }

    private void PdfDelete_Click(object sender, RoutedEventArgs e)
    {
        var selectedFiles = PdfFileGrid.SelectedItems
            .Cast<PdfFileRow>()
            .Select(r => r.Name)
            .ToList();

        if (selectedFiles.Count == 0 && PdfFileGrid.SelectedItem is PdfFileRow one)
            selectedFiles.Add(one.Name);

        if (selectedFiles.Count == 0) return;

        var folder = _hub.PdfFolder.CurrentFolder;
        if (string.IsNullOrEmpty(folder)) return;

        var confirm = MessageBox.Show(
            selectedFiles.Count == 1
                ? $"Permanently delete '{selectedFiles[0]}'?"
                : $"Permanently delete {selectedFiles.Count} selected PDFs?",
            "Delete PDF",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (confirm != MessageBoxResult.Yes) return;

        try
        {
            foreach (var selected in selectedFiles)
            {
                var fullPath = Path.Combine(folder, selected);
                if (File.Exists(fullPath))
                    File.Delete(fullPath);
            }
            StatusText = selectedFiles.Count == 1
                ? $"Deleted: {selectedFiles[0]}"
                : $"Deleted {selectedFiles.Count} PDFs";
        }
        catch (Exception ex)
        {
            StatusText = $"Delete failed: {ex.Message}";
        }
    }

    private async void PdfScale_Click(object sender, RoutedEventArgs e)
    {
        if (PdfFileGrid.SelectedItem is not PdfFileRow selectedRow)
        {
            StatusText = "Select a PDF in the list first.";
            return;
        }

        var selected = selectedRow.Name;

        var folder = _hub.PdfFolder.CurrentFolder;
        if (string.IsNullOrEmpty(folder)) return;

        var inputPath = Path.Combine(folder, selected);

        // Read source page size so presets can compute exact scales
        double srcW = 612, srcH = 792; // fallback: Letter
        try
        {
            using var probe = PdfSharp.Pdf.IO.PdfReader.Open(inputPath, PdfSharp.Pdf.IO.PdfDocumentOpenMode.Import);
            if (probe.PageCount > 0)
            {
                srcW = probe.Pages[0].Width.Point;
                srcH = probe.Pages[0].Height.Point;
            }
        }
        catch { /* use fallback */ }

        var opts = ShowScaleDialog(srcW, srcH);
        if (opts is null) return;

        StatusText = $"Scaling {selected}…";
        try
        {
            var outputPath = await Task.Run(() => PdfResizeService.Scale(inputPath, opts));
            StatusText = $"Saved: {Path.GetFileName(outputPath)}";
        }
        catch (Exception ex)
        {
            StatusText = $"Scale failed: {ex.Message}";
        }
    }

    private PdfScaleOptions? ShowScaleDialog(double srcW, double srcH)
    {
        PdfScaleOptions? result = null;

        // ── Helpers ───────────────────────────────────────────────────────────
        Brush Fg(byte r, byte g, byte b) =>
            new SolidColorBrush(Color.FromRgb(r, g, b));

        TextBox MakeInput(string text) => new TextBox
        {
            Text            = text,
            FontFamily      = new System.Windows.Media.FontFamily("Consolas"),
            FontSize        = 13,
            Width           = 72,
            Background      = Fg(0x3C, 0x3C, 0x3C),
            Foreground      = Fg(0xD4, 0xD4, 0xD4),
            CaretBrush      = new SolidColorBrush(Colors.White),
            BorderBrush     = Fg(0x55, 0x55, 0x55),
            BorderThickness = new Thickness(1),
            Padding         = new Thickness(6, 3, 6, 3),
            TextAlignment   = TextAlignment.Center
        };

        TextBlock MakeLabel(string text, bool muted = false) => new TextBlock
        {
            Text              = text,
            Foreground        = muted ? Fg(0x85, 0x85, 0x85) : Fg(0xD4, 0xD4, 0xD4),
            FontFamily        = new System.Windows.Media.FontFamily("Segoe UI"),
            FontSize          = 12,
            VerticalAlignment = VerticalAlignment.Center
        };

        Button MakeBtn(string text, bool primary = false) => new Button
        {
            Content         = text,
            Padding         = new Thickness(primary ? 20 : 14, 6, primary ? 20 : 14, 6),
            Margin          = new Thickness(0, 0, 6, 0),
            Background      = primary ? Fg(0x00, 0x7A, 0xCC) : Fg(0x3C, 0x3C, 0x3C),
            Foreground      = primary ? new SolidColorBrush(Colors.White) : Fg(0xD4, 0xD4, 0xD4),
            BorderBrush     = primary ? Fg(0x00, 0x7A, 0xCC) : Fg(0x55, 0x55, 0x55),
            BorderThickness = new Thickness(1),
            FontFamily      = new System.Windows.Media.FontFamily("Segoe UI"),
            FontSize        = 12,
            Cursor          = System.Windows.Input.Cursors.Hand
        };

        Separator MakeSep() => new Separator
        {
            Background = Fg(0x3C, 0x3C, 0x3C),
            Margin     = new Thickness(0, 10, 0, 10)
        };

        // ── Dialog ────────────────────────────────────────────────────────────
        var dlg = new Window
        {
            Title                 = "Scale PDF",
            Width                 = 420,
            SizeToContent         = SizeToContent.Height,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode            = ResizeMode.NoResize,
            WindowStyle           = WindowStyle.ToolWindow,
            Background            = Fg(0x25, 0x25, 0x26),
            ShowInTaskbar         = false,
            Owner                 = this
        };

        var root = new StackPanel { Margin = new Thickness(20) };

        // ── Presets ───────────────────────────────────────────────────────────
        root.Children.Add(MakeLabel("Preset page size"));
        var presetPanel = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
        foreach (var kv in PdfResizeService.Presets)
        {
            var pb = MakeBtn(kv.Key);
            pb.Margin = new Thickness(0, 0, 6, 6);
            presetPanel.Children.Add(pb);
        }
        root.Children.Add(presetPanel);
        root.Children.Add(MakeSep());

        // ── Lock aspect ratio ─────────────────────────────────────────────────
        var lockRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 10) };
        var lockChk = new CheckBox { IsChecked = true, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
        lockRow.Children.Add(lockChk);
        lockRow.Children.Add(MakeLabel("Lock aspect ratio"));
        root.Children.Add(lockRow);

        // ── X / Y inputs ──────────────────────────────────────────────────────
        var xRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8) };
        var tbX  = MakeInput("100");
        xRow.Children.Add(tbX);
        xRow.Children.Add(new TextBlock { Text = "%", Foreground = Fg(0x85, 0x85, 0x85), FontSize = 12, Margin = new Thickness(4, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center });
        xRow.Children.Add(MakeLabel("Horizontal (X)"));
        root.Children.Add(xRow);

        var yRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8) };
        var tbY  = MakeInput("100");
        yRow.Children.Add(tbY);
        yRow.Children.Add(new TextBlock { Text = "%", Foreground = Fg(0x85, 0x85, 0x85), FontSize = 12, Margin = new Thickness(4, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center });
        yRow.Children.Add(MakeLabel("Vertical (Y)"));
        root.Children.Add(yRow);

        // ── DPI ───────────────────────────────────────────────────────────────
        root.Children.Add(MakeSep());
        var dpiRow = new StackPanel { Orientation = Orientation.Horizontal };
        var tbDpi  = MakeInput("150");
        dpiRow.Children.Add(tbDpi);
        dpiRow.Children.Add(new TextBlock { Text = "DPI", Foreground = Fg(0x85, 0x85, 0x85), FontSize = 12, Margin = new Thickness(8, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center });
        dpiRow.Children.Add(MakeLabel("Render quality", muted: true));
        root.Children.Add(dpiRow);
        root.Children.Add(new TextBlock { Text = "Higher DPI = sharper raster images; 72–300 recommended", Foreground = Fg(0x60, 0x60, 0x60), FontSize = 11, Margin = new Thickness(0, 3, 0, 0) });

        // ── Action buttons ────────────────────────────────────────────────────
        root.Children.Add(MakeSep());
        var btnRow    = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var okBtn     = MakeBtn("Scale", primary: true);
        var cancelBtn = MakeBtn("Cancel");
        btnRow.Children.Add(okBtn);
        btnRow.Children.Add(cancelBtn);
        root.Children.Add(btnRow);

        dlg.Content = root;

        // ── Aspect lock ───────────────────────────────────────────────────────
        bool syncing = false;
        tbX.TextChanged += (_, _) =>
        {
            if (syncing || lockChk.IsChecked != true) return;
            syncing = true; tbY.Text = tbX.Text; syncing = false;
        };
        tbY.TextChanged += (_, _) =>
        {
            if (syncing || lockChk.IsChecked != true) return;
            syncing = true; tbX.Text = tbY.Text; syncing = false;
        };

        // ── Wire preset buttons ───────────────────────────────────────────────
        foreach (Button pb in presetPanel.Children)
        {
            var presetKey = (string)pb.Content;
            pb.Click += (_, _) =>
            {
                var (sx, sy) = PdfResizeService.ScaleForPreset(presetKey, srcW, srcH);
                syncing = true;
                tbX.Text = Math.Round(sx * 100, 1).ToString();
                tbY.Text = Math.Round(sy * 100, 1).ToString();
                syncing = false;
                lockChk.IsChecked = Math.Abs(sx - sy) < 0.001;
            };
        }

        // ── Validate & confirm ────────────────────────────────────────────────
        bool Validate(out double sx, out double sy, out int dpi)
        {
            sx = sy = 0; dpi = 0;
            return double.TryParse(tbX.Text, out sx)  && sx  >= 10 && sx  <= 1000 &&
                   double.TryParse(tbY.Text, out sy)  && sy  >= 10 && sy  <= 1000 &&
                   int.TryParse(tbDpi.Text,  out dpi) && dpi >= 36 && dpi <= 600;
        }

        okBtn.Click += (_, _) =>
        {
            if (Validate(out var sx, out var sy, out var dpi))
            {
                result           = new PdfScaleOptions(sx / 100.0, sy / 100.0, dpi);
                dlg.DialogResult = true;
            }
            else
            {
                tbX.BorderBrush  = Fg(0xFF, 0x45, 0x00);
                tbY.BorderBrush  = Fg(0xFF, 0x45, 0x00);
                tbDpi.BorderBrush = Fg(0xFF, 0x45, 0x00);
            }
        };

        cancelBtn.Click += (_, _) => dlg.DialogResult = false;

        dlg.Loaded += (_, _) => { tbX.Focus(); tbX.SelectAll(); };
        dlg.ShowDialog();
        return result;
    }

    // ── PDF Editor handlers ───────────────────────────────────────────────────

    private bool _pdfEditorSyncing;
    private string? _pdfEditorCurrentFile;
    private bool _pdfEditorIsEditMode = true;
    private System.Windows.Media.Imaging.BitmapSource? _pdfEditorBasePreview;
    private readonly System.Collections.ObjectModel.ObservableCollection<RunOverrideRow> _runOverrides = new();
    private List<string> _pdfEditorPageLines = [];
    private List<PdfTextLayoutRun> _pdfEditorLayoutRuns = [];

    private async void PdfFileGrid_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (PdfFileGrid.SelectedItem is not PdfFileRow row)
        {
            _pdfEditorCurrentFile = null;
            _pdfEditorBasePreview = null;
            _pdfEditorPageLines.Clear();
            _pdfEditorLayoutRuns.Clear();
            PdfEditorSelectedFileText.Text = "Select a PDF from the list above";
            PdfEditorImage.Source = null;
            PdfEditorOverlay.Children.Clear();
            return;
        }

        _pdfEditorCurrentFile = row.Name;
        PdfEditorSelectedFileText.Text = row.Name;

        var folder = _hub.PdfFolder.CurrentFolder;
        if (string.IsNullOrEmpty(folder))
        {
            StatusText = "Select a PDF folder first.";
            return;
        }

        await LoadPdfOverridesAsync(row.Name);
        await RenderPdfPreviewAsync(folder, row.Name);
    }

    private async Task LoadPdfOverridesAsync(string filename)
    {
        try
        {
            using var http = new System.Net.Http.HttpClient();
            var url  = $"http://localhost:{HubServer.Port}/api/pdf-overrides/{Uri.EscapeDataString(filename)}";
            var json = await http.GetStringAsync(url);
            ApplyOverridesJson(json);
        }
        catch
        {
            ResetEditorToDefaults();
        }
    }

    private void ApplyOverridesJson(string json)
    {
        _pdfEditorSyncing = true;
        try
        {
            using var doc  = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.TryGetProperty("global", out var global))
            {
                var sldPageSizeX = GetPageSizeXSlider();
                var sldPageSizeY = GetPageSizeYSlider();
                var txtPageSizeX = GetPageSizeXTextBox();
                var txtPageSizeY = GetPageSizeYTextBox();

                if (global.TryGetProperty("textSizeY",   out var v)  && v.TryGetDouble(out var d))
                    SetSliderAndText(SldSizeY, TxtSizeY, d * 100);
                if (global.TryGetProperty("textSizeX",   out var v2) && v2.TryGetDouble(out var d2))
                    SetSliderAndText(SldSizeX, TxtSizeX, d2 * 100);
                if (global.TryGetProperty("pageZoomX",   out var v3) && v3.TryGetDouble(out var d3))
                    SetSliderAndText(SldZoomX, TxtZoomX, d3 * 100);
                if (global.TryGetProperty("pageZoomY",   out var v4) && v4.TryGetDouble(out var d4))
                    SetSliderAndText(SldZoomY, TxtZoomY, d4 * 100);
                if (sldPageSizeX is not null && txtPageSizeX is not null
                    && global.TryGetProperty("pageSizeX", out var v5) && v5.TryGetDouble(out var d5))
                    SetSliderAndText(sldPageSizeX, txtPageSizeX, d5 * 100);
                if (sldPageSizeY is not null && txtPageSizeY is not null
                    && global.TryGetProperty("pageSizeY", out var v6) && v6.TryGetDouble(out var d6))
                    SetSliderAndText(sldPageSizeY, txtPageSizeY, d6 * 100);
                if (global.TryGetProperty("fontOverride", out var vf))
                    TxtFont.Text = vf.GetString() ?? string.Empty;
                if (global.TryGetProperty("forceBold",   out var vb))
                    ChkBold.IsChecked = vb.GetBoolean();
            }

            _runOverrides.Clear();
            if (root.TryGetProperty("runs", out var runs))
            {
                foreach (var prop in runs.EnumerateObject())
                {
                    var parts = prop.Name.TrimStart('p').Split(":r");
                    if (parts.Length != 2
                        || !int.TryParse(parts[0], out var page)
                        || !int.TryParse(parts[1], out var run))
                        continue;

                    var overrideRow = new RunOverrideRow { Page = page, RunIndex = run };
                    if (prop.Value.TryGetProperty("dx",        out var dx)  && dx.TryGetDouble(out var dxVal))
                        overrideRow.NudgeX = dxVal;
                    if (prop.Value.TryGetProperty("dy",        out var dy)  && dy.TryGetDouble(out var dyVal))
                        overrideRow.NudgeY = dyVal;
                    if (prop.Value.TryGetProperty("sizeScale", out var ss)  && ss.TryGetDouble(out var ssVal))
                        overrideRow.SizeScale = ssVal * 100;
                    _runOverrides.Add(overrideRow);
                }
            }

            RunOverridesGrid.ItemsSource = _runOverrides;
            RefreshPdfEditorSurface();
        }
        catch
        {
            ResetEditorToDefaults();
        }
        finally
        {
            _pdfEditorSyncing = false;
        }
    }

    private void ResetEditorToDefaults()
    {
        _pdfEditorSyncing = true;
        var sldPageSizeX = GetPageSizeXSlider();
        var sldPageSizeY = GetPageSizeYSlider();
        var txtPageSizeX = GetPageSizeXTextBox();
        var txtPageSizeY = GetPageSizeYTextBox();
        SetSliderAndText(SldSizeY, TxtSizeY, 175);
        SetSliderAndText(SldSizeX, TxtSizeX, 100);
        SetSliderAndText(SldZoomX, TxtZoomX, 100);
        SetSliderAndText(SldZoomY, TxtZoomY, 100);
        if (sldPageSizeX is not null && txtPageSizeX is not null)
            SetSliderAndText(sldPageSizeX, txtPageSizeX, 100);
        if (sldPageSizeY is not null && txtPageSizeY is not null)
            SetSliderAndText(sldPageSizeY, txtPageSizeY, 100);
        TxtFont.Text      = string.Empty;
        ChkBold.IsChecked = false;
        _runOverrides.Clear();
        RunOverridesGrid.ItemsSource = _runOverrides;
        _pdfEditorSyncing = false;
        RefreshPdfEditorSurface();
    }

    private void SetSliderAndText(Slider sld, TextBox txt, double value)
    {
        txt.Text  = ((int)Math.Round(value)).ToString();
        sld.Value = Math.Clamp(value, sld.Minimum, sld.Maximum);
    }

    private Slider? GetPageSizeXSlider() => FindName("SldPageSizeX") as Slider;
    private Slider? GetPageSizeYSlider() => FindName("SldPageSizeY") as Slider;
    private TextBox? GetPageSizeXTextBox() => FindName("TxtPageSizeX") as TextBox;
    private TextBox? GetPageSizeYTextBox() => FindName("TxtPageSizeY") as TextBox;

    private void FontCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_pdfEditorSyncing) return;
        RefreshPdfEditorSurface();
    }

    private void GlobalSetting_Changed(object sender, RoutedEventArgs e)
    {
        var sldPageSizeX = GetPageSizeXSlider();
        var sldPageSizeY = GetPageSizeYSlider();
        var txtPageSizeX = GetPageSizeXTextBox();
        var txtPageSizeY = GetPageSizeYTextBox();
        if (_pdfEditorSyncing || SldSizeY is null || SldSizeX is null || SldZoomX is null || SldZoomY is null || sldPageSizeX is null || sldPageSizeY is null || txtPageSizeX is null || txtPageSizeY is null) return;
        if (sender is not TextBox tb) return;
        _pdfEditorSyncing = true;
        try
        {
            if      (tb == TxtSizeY && double.TryParse(tb.Text, out var v))
                SldSizeY.Value = Math.Clamp(v, SldSizeY.Minimum, SldSizeY.Maximum);
            else if (tb == TxtSizeX && double.TryParse(tb.Text, out var v2))
                SldSizeX.Value = Math.Clamp(v2, SldSizeX.Minimum, SldSizeX.Maximum);
            else if (tb == TxtZoomX && double.TryParse(tb.Text, out var v3))
                SldZoomX.Value = Math.Clamp(v3, SldZoomX.Minimum, SldZoomX.Maximum);
            else if (tb == TxtZoomY && double.TryParse(tb.Text, out var v4))
                SldZoomY.Value = Math.Clamp(v4, SldZoomY.Minimum, SldZoomY.Maximum);
            else if (tb == txtPageSizeX && double.TryParse(tb.Text, out var v5))
                sldPageSizeX.Value = Math.Clamp(v5, sldPageSizeX.Minimum, sldPageSizeX.Maximum);
            else if (tb == txtPageSizeY && double.TryParse(tb.Text, out var v6))
                sldPageSizeY.Value = Math.Clamp(v6, sldPageSizeY.Minimum, sldPageSizeY.Maximum);
        }
        finally
        {
            _pdfEditorSyncing = false;
        }

        RefreshPdfEditorSurface();
    }

    private void SldSizeY_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_pdfEditorSyncing || TxtSizeY is null) return;
        _pdfEditorSyncing = true;
        TxtSizeY.Text = ((int)Math.Round(e.NewValue)).ToString();
        _pdfEditorSyncing = false;
        RefreshPdfEditorSurface();
    }

    private void SldSizeX_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_pdfEditorSyncing || TxtSizeX is null) return;
        _pdfEditorSyncing = true;
        TxtSizeX.Text = ((int)Math.Round(e.NewValue)).ToString();
        _pdfEditorSyncing = false;
        RefreshPdfEditorSurface();
    }

    private void SldZoomX_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_pdfEditorSyncing || TxtZoomX is null) return;
        _pdfEditorSyncing = true;
        TxtZoomX.Text = ((int)Math.Round(e.NewValue)).ToString();
        _pdfEditorSyncing = false;
        RefreshPdfEditorSurface();
    }

    private void SldZoomY_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_pdfEditorSyncing || TxtZoomY is null) return;
        _pdfEditorSyncing = true;
        TxtZoomY.Text = ((int)Math.Round(e.NewValue)).ToString();
        _pdfEditorSyncing = false;
        RefreshPdfEditorSurface();
    }

    private void SldPageSizeX_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        var txtPageSizeX = GetPageSizeXTextBox();
        if (_pdfEditorSyncing || txtPageSizeX is null) return;
        _pdfEditorSyncing = true;
        txtPageSizeX.Text = ((int)Math.Round(e.NewValue)).ToString();
        _pdfEditorSyncing = false;
        RefreshPdfEditorSurface();
    }

    private void SldPageSizeY_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        var txtPageSizeY = GetPageSizeYTextBox();
        if (_pdfEditorSyncing || txtPageSizeY is null) return;
        _pdfEditorSyncing = true;
        txtPageSizeY.Text = ((int)Math.Round(e.NewValue)).ToString();
        _pdfEditorSyncing = false;
        RefreshPdfEditorSurface();
    }

    private void RunOverrides_CellEditEnding(object sender, DataGridCellEditEndingEventArgs e)
    {
        Dispatcher.InvokeAsync(RefreshPdfEditorSurface);
    }

    private void PdfEditorEditMode_Click(object sender, RoutedEventArgs e)
    {
        _pdfEditorIsEditMode = true;
        UpdatePdfEditorModeUi();
        RefreshPdfEditorSurface();
    }

    private void PdfEditorViewMode_Click(object sender, RoutedEventArgs e)
    {
        _pdfEditorIsEditMode = false;
        UpdatePdfEditorModeUi();
        RefreshPdfEditorSurface();
    }

    private async void PdfEditorSave_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_pdfEditorCurrentFile)) return;

        var payload = BuildOverridesPayload();
        var json    = JsonSerializer.Serialize(payload,
            new JsonSerializerOptions { WriteIndented = true });

        try
        {
            using var http    = new System.Net.Http.HttpClient();
            var url           = $"http://localhost:{HubServer.Port}/api/pdf-overrides/{Uri.EscapeDataString(_pdfEditorCurrentFile)}";
            var content       = new System.Net.Http.StringContent(json, System.Text.Encoding.UTF8, "application/json");
            var response      = await http.PostAsync(url, content);
            StatusText = response.IsSuccessStatusCode
                ? $"Saved: {_pdfEditorCurrentFile}"
                : $"Save failed: {(int)response.StatusCode}";
        }
        catch (Exception ex)
        {
            StatusText = $"Save failed: {ex.Message}";
        }
    }

    private object BuildOverridesPayload()
    {
        var txtPageSizeX = GetPageSizeXTextBox();
        var txtPageSizeY = GetPageSizeYTextBox();
        double sizeY = double.TryParse(TxtSizeY.Text, out var v1) ? v1 / 100.0 : 1.75;
        double sizeX = double.TryParse(TxtSizeX.Text, out var v2) ? v2 / 100.0 : 1.0;
        double zoomX = double.TryParse(TxtZoomX.Text, out var v3) ? v3 / 100.0 : 1.0;
        double zoomY = double.TryParse(TxtZoomY.Text, out var v4) ? v4 / 100.0 : 1.0;
        double pageSizeX = double.TryParse(txtPageSizeX?.Text, out var v5) ? v5 / 100.0 : 1.0;
        double pageSizeY = double.TryParse(txtPageSizeY?.Text, out var v6) ? v6 / 100.0 : 1.0;

        var runsDict = new Dictionary<string, object>();
        foreach (RunOverrideRow row in _runOverrides)
            runsDict[$"p{row.Page}:r{row.RunIndex}"] = new
            {
                dx        = row.NudgeX,
                dy        = row.NudgeY,
                sizeScale = row.SizeScale / 100.0
            };

        return new
        {
            global = new
            {
                textSizeY    = sizeY,
                textSizeX    = sizeX,
                pageZoomX    = zoomX,
                pageZoomY    = zoomY,
                pageSizeX    = pageSizeX,
                pageSizeY    = pageSizeY,
                forceBold    = ChkBold.IsChecked == true,
                fontOverride = TxtFont.Text.Trim()
            },
            runs = runsDict
        };
    }

    private async Task RenderPdfPreviewAsync(string folder, string filename)
    {
        try
        {
            var path = Path.Combine(folder, filename);
            if (!File.Exists(path))
            {
                _pdfEditorBasePreview = null;
                _pdfEditorPageLines.Clear();
                _pdfEditorLayoutRuns.Clear();
                PdfEditorImage.Source = null;
                PdfEditorOverlay.Children.Clear();
                StatusText = $"Preview file not found: {filename}";
                return;
            }

            // Render preview synchronously on the UI thread to avoid cross-thread bitmap issues.
            System.Windows.Media.Imaging.BitmapSource? bmp = RenderPageToBitmapSource(path);

            if (bmp is null)
            {
                _pdfEditorBasePreview = null;
                _pdfEditorPageLines.Clear();
                _pdfEditorLayoutRuns.Clear();
                PdfEditorImage.Source = null;
                PdfEditorOverlay.Children.Clear();
                StatusText = $"Preview failed for: {filename}";
                return;
            }

            _pdfEditorBasePreview = bmp;
            _pdfEditorLayoutRuns = await ExtractPageLayoutRunsAsync(path, bmp.Width, bmp.Height);
            _pdfEditorPageLines = _pdfEditorLayoutRuns.Select(r => r.Text).ToList();
            SyncRunOverridePreviewText();
            RefreshPdfEditorSurface();
            StatusText = $"Preview loaded: {filename}";
        }
        catch (Exception ex)
        {
            _pdfEditorBasePreview = null;
            _pdfEditorPageLines.Clear();
            _pdfEditorLayoutRuns.Clear();
            PdfEditorImage.Source = null;
            PdfEditorOverlay.Children.Clear();
            StatusText = $"Preview error: {ex.Message}";
        }
    }

    private void RefreshPdfEditorSurface()
    {
        if (PdfEditorImage is null || PdfEditorOverlay is null || PdfEditorCanvas is null)
            return;

        if (_pdfEditorBasePreview is null)
        {
            PdfEditorImage.Source = null;
            PdfEditorCanvas.LayoutTransform = Transform.Identity;
            PdfEditorOverlay.Children.Clear();
            return;
        }

        var surface = _pdfEditorIsEditMode
            ? _pdfEditorBasePreview
            : BuildComposedViewBitmap(_pdfEditorBasePreview);

        var txtPageSizeX = GetPageSizeXTextBox();
        var txtPageSizeY = GetPageSizeYTextBox();
        double pageScaleX = Math.Clamp(ParsePercentOrDefault(txtPageSizeX?.Text, 100), 10, 500) / 100.0;
        double pageScaleY = Math.Clamp(ParsePercentOrDefault(txtPageSizeY?.Text, 100), 10, 500) / 100.0;

        PdfEditorImage.Source = surface;
        PdfEditorCanvas.Width = surface.PixelWidth;
        PdfEditorCanvas.Height = surface.PixelHeight;
        PdfEditorCanvas.LayoutTransform = new ScaleTransform(pageScaleX, pageScaleY);
        RefreshPdfEditorOverlay();
    }

    private System.Windows.Media.Imaging.BitmapSource BuildComposedViewBitmap(System.Windows.Media.Imaging.BitmapSource basePreview)
    {
        try
        {
            double width = basePreview.Width;
            double height = basePreview.Height;
            if (width <= 0 || height <= 0)
                return basePreview;

            double zoomX = Math.Clamp(ParsePercentOrDefault(TxtZoomX?.Text, 100), 10, 1000) / 100.0;
            double zoomY = Math.Clamp(ParsePercentOrDefault(TxtZoomY?.Text, 100), 10, 1000) / 100.0;
            double sizeY = Math.Clamp(ParsePercentOrDefault(TxtSizeY?.Text, 175), 10, 1000) / 100.0;
            double sizeX = Math.Clamp(ParsePercentOrDefault(TxtSizeX?.Text, 100), 10, 1000) / 100.0;

            var visual = new DrawingVisual();
            using (var dc = visual.RenderOpen())
            {
                // Edited view: show only composed text output, not original PDF raster.
                dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, width, height));

                string fontName = TxtFont?.Text?.Trim() ?? string.Empty;
                FontFamily fontFamily;
                try
                {
                    fontFamily = string.IsNullOrWhiteSpace(fontName)
                        ? new FontFamily("Segoe UI")
                        : new FontFamily(fontName);
                }
                catch
                {
                    fontFamily = new FontFamily("Segoe UI");
                }

                var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
                var textBrush = new SolidColorBrush(Color.FromRgb(0x11, 0x11, 0x11));
                var textWeight = ChkBold?.IsChecked == true ? FontWeights.Bold : FontWeights.Normal;

                var overrideMap = _runOverrides
                    .Where(r => r.Page <= 1)
                    .GroupBy(r => r.RunIndex)
                    .ToDictionary(g => g.Key, g => g.Last());

                for (int i = 0; i < _pdfEditorLayoutRuns.Count; i++)
                {
                    var layout = _pdfEditorLayoutRuns[i];
                    overrideMap.TryGetValue(layout.RunIndex, out var runOverride);

                    var label = string.IsNullOrWhiteSpace(runOverride?.PreviewText)
                        ? layout.Text
                        : runOverride!.PreviewText;
                    double runSizeScale = Math.Max(0.1, (runOverride?.SizeScale ?? 100.0) / 100.0);
                    double rowFont = Math.Max(6, layout.Height * sizeY * runSizeScale);

                    var runText = new FormattedText(
                        label,
                        CultureInfo.CurrentUICulture,
                        FlowDirection.LeftToRight,
                        new Typeface(fontFamily, FontStyles.Normal, textWeight, FontStretches.Normal),
                        rowFont,
                        textBrush,
                        dpi);

                    double centeredX = ((layout.X - (width / 2.0)) * zoomX) + (width / 2.0);
                    double centeredY = ((layout.Y - (height / 2.0)) * zoomY) + (height / 2.0);
                    double drawX = centeredX + (runOverride?.NudgeX ?? 0);
                    double drawY = centeredY + (runOverride?.NudgeY ?? 0);
                    double maxX = Math.Max(0, width - runText.Width);
                    double maxY = Math.Max(0, height - runText.Height);
                    drawX = Math.Clamp(drawX, 0, maxX);
                    drawY = Math.Clamp(drawY, 0, maxY);

                    if (Math.Abs(sizeX - 1.0) > 0.001)
                    {
                        dc.PushTransform(new ScaleTransform(sizeX, 1.0, drawX, drawY));
                        dc.DrawText(runText, new Point(drawX, drawY));
                        dc.Pop();
                    }
                    else
                    {
                        dc.DrawText(runText, new Point(drawX, drawY));
                    }
                }

                if (_pdfEditorLayoutRuns.Count == 0)
                {
                    var emptyText = new FormattedText(
                        "No positioned text runs were detected on page 1.",
                        CultureInfo.CurrentUICulture,
                        FlowDirection.LeftToRight,
                        new Typeface(new FontFamily("Segoe UI"), FontStyles.Italic, FontWeights.Normal, FontStretches.Normal),
                        12,
                        new SolidColorBrush(Color.FromRgb(0x66, 0x66, 0x66)),
                        dpi);
                    dc.DrawText(emptyText, new Point(12, 12));
                }
            }

            var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap(
                basePreview.PixelWidth,
                basePreview.PixelHeight,
                96,
                96,
                PixelFormats.Pbgra32);
            bitmap.Render(visual);
            bitmap.Freeze();
            return bitmap;
        }
        catch
        {
            return basePreview;
        }
    }

    private void SyncRunOverridePreviewText()
    {
        foreach (var row in _runOverrides)
        {
            if (row.Page > 1)
                continue;

            if (row.RunIndex >= 0 && row.RunIndex < _pdfEditorLayoutRuns.Count)
                row.PreviewText = _pdfEditorLayoutRuns[row.RunIndex].Text;
            else if (row.RunIndex > 0 && row.RunIndex - 1 < _pdfEditorLayoutRuns.Count)
                row.PreviewText = _pdfEditorLayoutRuns[row.RunIndex - 1].Text;
            else if (row.RunIndex >= 0 && row.RunIndex < _pdfEditorPageLines.Count)
                row.PreviewText = _pdfEditorPageLines[row.RunIndex];
            else if (row.RunIndex > 0 && row.RunIndex - 1 < _pdfEditorPageLines.Count)
                row.PreviewText = _pdfEditorPageLines[row.RunIndex - 1];
            else if (string.IsNullOrWhiteSpace(row.PreviewText))
                row.PreviewText = $"Run {row.RunIndex}";
        }
    }

    private void RefreshPdfEditorOverlay()
    {
        if (PdfEditorOverlay is null)
            return;

        PdfEditorOverlay.Children.Clear();

        if (!_pdfEditorIsEditMode)
            return;

        var source = PdfEditorImage.Source;
        if (source is null)
            return;

        var canvasW = PdfEditorCanvas.Width > 0 ? PdfEditorCanvas.Width : source.Width;
        var canvasH = PdfEditorCanvas.Height > 0 ? PdfEditorCanvas.Height : source.Height;
        if (canvasW <= 0 || canvasH <= 0)
            return;

        PdfEditorOverlay.Width = canvasW;
        PdfEditorOverlay.Height = canvasH;

        // Visual guide only: this does not rewrite PDF text yet.
        double sizeX = Math.Clamp(ParsePercentOrDefault(TxtSizeX?.Text, 100), 10, 1000) / 100.0;
        double sizeY = Math.Clamp(ParsePercentOrDefault(TxtSizeY?.Text, 175), 10, 1000) / 100.0;
        double zoomX = Math.Clamp(ParsePercentOrDefault(TxtZoomX?.Text, 100), 10, 1000) / 100.0;
        double zoomY = Math.Clamp(ParsePercentOrDefault(TxtZoomY?.Text, 100), 10, 1000) / 100.0;

        var guideW = Math.Clamp(canvasW * 0.42 * zoomX, 60, canvasW - 8);
        var guideH = Math.Clamp(canvasH * 0.14 * sizeY * zoomY, 24, canvasH - 8);
        var guideX = (canvasW - guideW) / 2;
        var guideY = Math.Max(8, canvasH * 0.12);

        var guide = new System.Windows.Shapes.Rectangle
        {
            Width = guideW,
            Height = guideH,
            Stroke = new SolidColorBrush(Color.FromArgb(220, 0x00, 0xE5, 0xFF)),
            StrokeThickness = 2,
            Fill = new SolidColorBrush(Color.FromArgb(52, 0x00, 0xE5, 0xFF)),
            RadiusX = 4,
            RadiusY = 4
        };
        Canvas.SetLeft(guide, guideX);
        Canvas.SetTop(guide, guideY);
        PdfEditorOverlay.Children.Add(guide);

        var globalLabel = new TextBlock
        {
            Text = $"Preview overlay | X {sizeX:P0}  Y {sizeY:P0}  ZX {zoomX:P0}  ZY {zoomY:P0}",
            Foreground = Brushes.White,
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Background = new SolidColorBrush(Color.FromArgb(170, 0, 0, 0)),
            Padding = new Thickness(6, 3, 6, 3)
        };
        Canvas.SetLeft(globalLabel, 8);
        Canvas.SetTop(globalLabel, 8);
        PdfEditorOverlay.Children.Add(globalLabel);

        for (int i = 0; i < _runOverrides.Count; i++)
        {
            var run = _runOverrides[i];
            var y = guideY + guideH + 10 + (i * 20);
            if (y > canvasH - 24)
                break;

            var runX = Math.Clamp(guideX + run.NudgeX, 8, Math.Max(8, canvasW - 120));
            var marker = new System.Windows.Shapes.Ellipse
            {
                Width = 7,
                Height = 7,
                Fill = new SolidColorBrush(Color.FromRgb(0xFF, 0xC1, 0x07))
            };
            Canvas.SetLeft(marker, runX);
            Canvas.SetTop(marker, y + Math.Clamp(run.NudgeY, -12, 12));
            PdfEditorOverlay.Children.Add(marker);

            var runLabel = new TextBlock
            {
                Text = $"p{run.Page}:r{run.RunIndex}  dx {run.NudgeX:0.##}  dy {run.NudgeY:0.##}  size {run.SizeScale:0.#}%",
                Foreground = Brushes.White,
                FontSize = 11,
                Background = new SolidColorBrush(Color.FromArgb(150, 25, 25, 25)),
                Padding = new Thickness(4, 2, 4, 2)
            };
            Canvas.SetLeft(runLabel, Math.Min(runX + 10, canvasW - 260));
            Canvas.SetTop(runLabel, y - 4);
            PdfEditorOverlay.Children.Add(runLabel);
        }
    }

    private static double ParsePercentOrDefault(string? text, double defaultValue)
        => double.TryParse(text, out var value) ? value : defaultValue;

    private sealed class PdfTextLayoutRun
    {
        public int RunIndex { get; init; }
        public string Text { get; init; } = string.Empty;
        public double X { get; init; }
        public double Y { get; init; }
        public double Height { get; init; }
    }

    private static async Task<List<PdfTextLayoutRun>> ExtractPageLayoutRunsAsync(
        string pdfPath, double targetWidth, double targetHeight)
    {
        try
        {
            var encoded  = Uri.EscapeDataString(pdfPath);
            var response = await CTHub.Services.PdfSidecarService.Http
                .GetAsync($"/words?path={encoded}");

            if (!response.IsSuccessStatusCode) return [];

            var json = await response.Content.ReadAsStringAsync();
            using var doc = System.Text.Json.JsonDocument.Parse(json);

            var pages = doc.RootElement.GetProperty("pages");
            if (pages.GetArrayLength() == 0) return [];

            var firstPage = pages[0];
            double pageW  = firstPage.GetProperty("width").GetDouble();
            double pageH  = firstPage.GetProperty("height").GetDouble();
            if (pageW <= 0 || pageH <= 0) return [];

            double scaleX = targetWidth  / pageW;
            double scaleY = targetHeight / pageH;

            var runs  = new List<PdfTextLayoutRun>();
            var words = firstPage.GetProperty("words");
            int i = 0;
            foreach (var word in words.EnumerateArray())
            {
                var text = word.GetProperty("text").GetString()?.Trim();
                if (string.IsNullOrWhiteSpace(text)) { i++; continue; }

                // Sidecar returns PDF-space coords (bottom-left origin).
                // y1 is the top of the word in PDF space; convert to UI space (top-left origin).
                double x  = word.GetProperty("x0").GetDouble() * scaleX;
                double y1 = word.GetProperty("y1").GetDouble();
                double y0 = word.GetProperty("y0").GetDouble();
                double y  = targetHeight - (y1 * scaleY);
                double h  = Math.Max(6, (y1 - y0) * scaleY);

                runs.Add(new PdfTextLayoutRun { RunIndex = i, Text = text, X = x, Y = y, Height = h });
                i++;
            }

            return runs;
        }
        catch
        {
            return [];
        }
    }

    private void UpdatePdfEditorModeUi()
    {
        var editButton = FindName("PdfEditorEditModeBtn") as Button;
        var viewButton = FindName("PdfEditorViewModeBtn") as Button;

        if (editButton is null || viewButton is null)
            return;

        ApplyPdfEditorModeButtonState(editButton, _pdfEditorIsEditMode);
        ApplyPdfEditorModeButtonState(viewButton, !_pdfEditorIsEditMode);
    }

    private static void ApplyPdfEditorModeButtonState(Button button, bool isActive)
    {
        if (isActive)
        {
            button.Background = new SolidColorBrush(Color.FromRgb(0x00, 0x7A, 0xCC));
            button.BorderBrush = new SolidColorBrush(Color.FromRgb(0x00, 0x7A, 0xCC));
            button.Foreground = Brushes.White;
            return;
        }

        button.Background = new SolidColorBrush(Color.FromRgb(0x3C, 0x3C, 0x3C));
        button.BorderBrush = new SolidColorBrush(Color.FromRgb(0x55, 0x55, 0x55));
        button.Foreground = new SolidColorBrush(Color.FromRgb(0xD4, 0xD4, 0xD4));
    }

    // Renders the first page of a PDF to a frozen WPF BitmapSource scaled to 390 px wide.
    // Called on the UI thread; returns null on any failure.
    private static System.Windows.Media.Imaging.BitmapSource? RenderPageToBitmapSource(string pdfPath)
    {
        string? tempPdfPath = null;
        try
        {
            var ext = Path.GetExtension(pdfPath);
            var normalizedPath = pdfPath;

            // Some upstream systems store valid PDF bytes with a .nl extension.
            if (!string.Equals(ext, ".pdf", StringComparison.OrdinalIgnoreCase))
            {
                tempPdfPath = Path.ChangeExtension(Path.GetTempFileName(), ".pdf");
                File.Copy(pdfPath, tempPdfPath, overwrite: true);
                normalizedPath = tempPdfPath;
            }

            // Use Windows.Data.Pdf (built into Windows 10+) — no external NuGet dependency.
            var file = Windows.Storage.StorageFile.GetFileFromPathAsync(
                Path.GetFullPath(normalizedPath)).GetAwaiter().GetResult();
            var pdfDoc = Windows.Data.Pdf.PdfDocument.LoadFromFileAsync(file)
                .GetAwaiter().GetResult();
            if (pdfDoc.PageCount == 0) return null;

            using var page = pdfDoc.GetPage(0);
            var pageSize = page.Size;
            if (pageSize.Width <= 0 || pageSize.Height <= 0) return null;

            const int targetWidth = 390;
            double scale = targetWidth / pageSize.Width;
            uint w = (uint)targetWidth;
            uint h = (uint)Math.Max(1, (int)Math.Round(pageSize.Height * scale));

            using var stream = new Windows.Storage.Streams.InMemoryRandomAccessStream();
            var options = new Windows.Data.Pdf.PdfPageRenderOptions
            {
                DestinationWidth  = w,
                DestinationHeight = h,
            };
            page.RenderToStreamAsync(stream, options).GetAwaiter().GetResult();
            stream.Seek(0);

            var bitmapImage = new System.Windows.Media.Imaging.BitmapImage();
            bitmapImage.BeginInit();
            bitmapImage.CacheOption  = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
            bitmapImage.StreamSource = stream.AsStreamForRead();
            bitmapImage.EndInit();
            bitmapImage.Freeze();
            return bitmapImage;
        }
        catch
        {
            return null;
        }
        finally
        {
            if (!string.IsNullOrEmpty(tempPdfPath) && File.Exists(tempPdfPath))
            {
                try { File.Delete(tempPdfPath); } catch { /* ignore temp cleanup failures */ }
            }
        }
    }
}

public sealed class RunOverrideRow : INotifyPropertyChanged
{
    private int    _page        = 1;
    private int    _runIndex;
    private string _previewText = string.Empty;
    private double _nudgeX;
    private double _nudgeY;
    private double _sizeScale   = 100;

    public int    Page        { get => _page;        set { _page        = value; OnPropertyChanged(); } }
    public int    RunIndex    { get => _runIndex;    set { _runIndex    = value; OnPropertyChanged(); } }
    public string PreviewText { get => _previewText; set { _previewText = value; OnPropertyChanged(); } }
    public double NudgeX      { get => _nudgeX;      set { _nudgeX      = value; OnPropertyChanged(); } }
    public double NudgeY      { get => _nudgeY;      set { _nudgeY      = value; OnPropertyChanged(); } }
    public double SizeScale   { get => _sizeScale;   set { _sizeScale   = value; OnPropertyChanged(); } }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([System.Runtime.CompilerServices.CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
