using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Net.Http;
using CTHub.Models;
using CTHub.Services;
using Microsoft.Win32;
using Microsoft.Web.WebView2.Core;
using ZXing;
using ZXing.Common;

namespace CTHub;

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private const double PdfEditorWebZoomMin = 0.30;
    private const double PdfEditorWebZoomMax = 4.0;
    private const double PdfEditorWebZoomDefault = 1.0;

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
    private readonly System.Windows.Threading.DispatcherTimer _chadHoldTimer;
    private bool _chadHandled = false;
    private bool _isDevToolsVisible = false;
    private bool _qrGenSyncing;
    private string _qrGenCurrentZpl = string.Empty;
    private double _pdfEditorWebZoomFactor = PdfEditorWebZoomDefault;
    private bool _applyingPdfEditorLayout;

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

    // ── Mobile Card Config ────────────────────────────────────────────────────

    // Field option lists (BindingPath + friendly label) for each table's ComboBoxes.
    // "(none)" maps to null — no field shown.
    private static readonly List<string?> _ctFields  = new() { null, "Bin", "ClassName", "ClassLetter", "ClassId", "Label", "Qty", "StockThreshold", "Notes" };
    private static readonly List<string?> _thFields  = new() { null, "Bin", "Sku", "Description", "Qty", "StockThreshold" };
    private static readonly List<string?> _ssFields  = new() { null, "Dimensions", "Bundle", "Single", "StockThreshold" };

    public IReadOnlyList<string?> MobileCardFieldOptions_CT => _ctFields;
    public IReadOnlyList<string?> MobileCardFieldOptions_TH => _thFields;
    public IReadOnlyList<string?> MobileCardFieldOptions_SS => _ssFields;

    private CTHub.Services.MobileCardEntry CardCfg(string table) =>
        _settings.MobileCardConfig.TryGetValue(table, out var e) ? e : new();

    private void SaveCardCfg(string table, CTHub.Services.MobileCardEntry entry)
    {
        _settings.MobileCardConfig[table] = entry;
        _settings.Save();
    }

    // Chase Tactical
    public string? MobileCard_CT_Row1
    {
        get => CardCfg("chasetactical").Row1;
        set { var e = CardCfg("chasetactical"); e.Row1 = value; SaveCardCfg("chasetactical", e); OnPropertyChanged(); }
    }
    public string? MobileCard_CT_Row2a
    {
        get => CardCfg("chasetactical").Row2.ElementAtOrDefault(0);
        set { var e = CardCfg("chasetactical"); var r2 = e.Row2.ToList(); if (r2.Count == 0) r2.Add(value!); else r2[0] = value!; e.Row2 = r2.Where(x => x != null).ToList()!; SaveCardCfg("chasetactical", e); OnPropertyChanged(); }
    }
    public string? MobileCard_CT_Row2b
    {
        get => CardCfg("chasetactical").Row2.ElementAtOrDefault(1);
        set { var e = CardCfg("chasetactical"); var r2 = e.Row2.ToList(); while (r2.Count < 2) r2.Add(null!); r2[1] = value!; e.Row2 = r2.Where(x => x != null).ToList()!; SaveCardCfg("chasetactical", e); OnPropertyChanged(); }
    }
    public string? MobileCard_CT_Badge
    {
        get => CardCfg("chasetactical").Badge;
        set { var e = CardCfg("chasetactical"); e.Badge = value; SaveCardCfg("chasetactical", e); OnPropertyChanged(); }
    }

    // Tough Hooks
    public string? MobileCard_TH_Row1
    {
        get => CardCfg("toughhooks").Row1;
        set { var e = CardCfg("toughhooks"); e.Row1 = value; SaveCardCfg("toughhooks", e); OnPropertyChanged(); }
    }
    public string? MobileCard_TH_Row2a
    {
        get => CardCfg("toughhooks").Row2.ElementAtOrDefault(0);
        set { var e = CardCfg("toughhooks"); var r2 = e.Row2.ToList(); if (r2.Count == 0) r2.Add(value!); else r2[0] = value!; e.Row2 = r2.Where(x => x != null).ToList()!; SaveCardCfg("toughhooks", e); OnPropertyChanged(); }
    }
    public string? MobileCard_TH_Row2b
    {
        get => CardCfg("toughhooks").Row2.ElementAtOrDefault(1);
        set { var e = CardCfg("toughhooks"); var r2 = e.Row2.ToList(); while (r2.Count < 2) r2.Add(null!); r2[1] = value!; e.Row2 = r2.Where(x => x != null).ToList()!; SaveCardCfg("toughhooks", e); OnPropertyChanged(); }
    }
    public string? MobileCard_TH_Badge
    {
        get => CardCfg("toughhooks").Badge;
        set { var e = CardCfg("toughhooks"); e.Badge = value; SaveCardCfg("toughhooks", e); OnPropertyChanged(); }
    }

    // Shipping Supplys
    public string? MobileCard_SS_Row1
    {
        get => CardCfg("shippingsupplys").Row1;
        set { var e = CardCfg("shippingsupplys"); e.Row1 = value; SaveCardCfg("shippingsupplys", e); OnPropertyChanged(); }
    }
    public string? MobileCard_SS_Row2a
    {
        get => CardCfg("shippingsupplys").Row2.ElementAtOrDefault(0);
        set { var e = CardCfg("shippingsupplys"); var r2 = e.Row2.ToList(); if (r2.Count == 0) r2.Add(value!); else r2[0] = value!; e.Row2 = r2.Where(x => x != null).ToList()!; SaveCardCfg("shippingsupplys", e); OnPropertyChanged(); }
    }
    public string? MobileCard_SS_Row2b
    {
        get => CardCfg("shippingsupplys").Row2.ElementAtOrDefault(1);
        set { var e = CardCfg("shippingsupplys"); var r2 = e.Row2.ToList(); while (r2.Count < 2) r2.Add(null!); r2[1] = value!; e.Row2 = r2.Where(x => x != null).ToList()!; SaveCardCfg("shippingsupplys", e); OnPropertyChanged(); }
    }
    public string? MobileCard_SS_Badge
    {
        get => CardCfg("shippingsupplys").Badge;
        set { var e = CardCfg("shippingsupplys"); e.Badge = value; SaveCardCfg("shippingsupplys", e); OnPropertyChanged(); }
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

    private bool _isPrivacyModeOn = true;
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

        QrGenUpcALeadDigit.ItemsSource = Enumerable.Range(0, 10);
        QrGenUpcALeadDigit.SelectedIndex = 0;

        _chadHoldTimer = new System.Windows.Threading.DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(3)
        };
        _chadHoldTimer.Tick += (_, _) =>
        {
            _chadHoldTimer.Stop();
            if (!IsChadComboPressed() || _chadHandled)
                return;

            _chadHandled = true;
            _isDevToolsVisible = !_isDevToolsVisible;
            UpdateDevToolsVisibility();
            AddDevCdpLog(_isDevToolsVisible
                ? "Dev Tools tab revealed via CHAD hold."
                : "Dev Tools tab hidden via CHAD hold.");
            StatusText = _isDevToolsVisible
                ? "Dev Tools revealed via CHAD hold."
                : "Dev Tools hidden via CHAD hold.";
        };

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
    PreviewKeyUp += MainWindow_PreviewKeyUp;
    Deactivated += (_, _) => CancelChadHold();
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
        InitializeQrGenerator();
        Loaded += (_, _) => Dispatcher.BeginInvoke(new Action(ApplySavedPdfEditorLayout), System.Windows.Threading.DispatcherPriority.Loaded);
        Loaded += (_, _) =>
        {
            SeedColumnsIfNeeded();
            RebuildAllDynamicColumns();
            QrMappingItems.CollectionChanged += (_, e) =>
            {
                if (e.Action != System.Collections.Specialized.NotifyCollectionChangedAction.Add) return;
                if (e.NewItems?[0] is not QrClassMapping added) return;
                Dispatcher.InvokeAsync(() =>
                {
                    // Set code type first so preview renders correctly when Text is set
                    if (added.QrValue.Length == 12 && added.QrValue.All(char.IsDigit))
                        QrGenTypeUpcA.IsChecked = true;
                    else if (added.QrValue.All(c => char.IsAsciiLetterOrDigit(c) || c == '-'))
                        QrGenTypeBarcode.IsChecked = true;
                    else
                        QrGenTypeQr.IsChecked = true;
                    // Fill payload — TextChanged fires UpdateQrGeneratorPreview() with correct type
                    QrGenPayload.Text = added.QrValue;
                    // Select + scroll the new row into view
                    QrMappingsGrid.SelectedItem = added;
                    QrMappingsGrid.ScrollIntoView(added);
                });
            };
            Dispatcher.BeginInvoke(new Action(ApplyAllGridLayouts), System.Windows.Threading.DispatcherPriority.Background);
        };

        // Populate server info panel
        RefreshServerInfo();
    }

    protected override async void OnClosed(EventArgs e)
    {
        SaveAllGridLayouts();
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
        UpdateChadHoldState();
    }

    private void MainWindow_PreviewKeyUp(object sender, KeyEventArgs e)
    {
        UpdateChadHoldState();
    }

    private static char? KeyToUpperChar(Key key)
    {
        if (key >= Key.A && key <= Key.Z)
            return (char)('A' + (key - Key.A));
        return null;
    }

    private bool IsChadComboPressed()
    {
        return Keyboard.IsKeyDown(Key.C)
            && Keyboard.IsKeyDown(Key.H)
            && Keyboard.IsKeyDown(Key.A)
            && Keyboard.IsKeyDown(Key.D);
    }

    private void UpdateChadHoldState()
    {
        if (IsChadComboPressed())
        {
            if (!_chadHandled && !_chadHoldTimer.IsEnabled)
                _chadHoldTimer.Start();
            return;
        }

        CancelChadHold();
    }

    private void CancelChadHold()
    {
        _chadHoldTimer.Stop();
        _chadHandled = false;
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
        _chaseView.GroupDescriptions.Add(new PropertyGroupDescription(nameof(ChaseTacticalEntry.SectionLabel)));

        _toughHooksView = CollectionViewSource.GetDefaultView(ToughHookItems);
        _toughHooksView.Filter = item => FilterToughHook(item as ToughHookEntry);
        _toughHooksView.GroupDescriptions.Add(new PropertyGroupDescription(nameof(ToughHookEntry.SectionLabel)));

        _shippingSupplysView = CollectionViewSource.GetDefaultView(ShippingSupplysItems);
        _shippingSupplysView.Filter = item => FilterShippingSupplys(item as ShippingSupplyEntry);
        _shippingSupplysView.GroupDescriptions.Add(new PropertyGroupDescription(nameof(ShippingSupplyEntry.SectionLabel)));

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
            || entry.Qty.ToString().Contains(term, StringComparison.OrdinalIgnoreCase)
            || entry.StockThreshold.ToString().Contains(term, StringComparison.OrdinalIgnoreCase);
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
            || entry.Qty.ToString().Contains(term, StringComparison.OrdinalIgnoreCase)
            || entry.StockThreshold.ToString().Contains(term, StringComparison.OrdinalIgnoreCase);
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
            || entry.StockThreshold.ToString().Contains(term, StringComparison.OrdinalIgnoreCase)
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

    // ── Backup / Restore ───────────────────────────────────────────────────

    private static readonly string _appDataDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CT-Hub");

    private string BackupDir => Path.Combine(
        AppContext.BaseDirectory, "..", "..", "..", "..", "CT-Hub-Data");

    private void BackupData_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dest = Path.GetFullPath(BackupDir);
            CopyDirectory(_appDataDir, dest);
            StatusText = $"Backup complete → {dest}";
            MessageBox.Show($"App data backed up to:\n{dest}", "CT Hub – Backup",
                MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Backup failed:\n{ex.Message}", "CT Hub – Backup",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void RestoreData_Click(object sender, RoutedEventArgs e)
    {
        var src = Path.GetFullPath(BackupDir);
        if (!Directory.Exists(src))
        {
            MessageBox.Show($"No backup folder found at:\n{src}\n\nRun Backup on the other computer first.",
                "CT Hub – Restore", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var result = MessageBox.Show(
            "This will overwrite your current app data with the backup. Continue?",
            "CT Hub – Restore", MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (result != MessageBoxResult.Yes) return;

        try
        {
            CopyDirectory(src, _appDataDir);
            StatusText = "Restore complete – restart CT Hub to load the restored data.";
            MessageBox.Show("Restore complete.\nPlease restart CT Hub to load the restored data.",
                "CT Hub – Restore", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Restore failed:\n{ex.Message}", "CT Hub – Restore",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private static void CopyDirectory(string sourceDir, string destDir)
    {
        Directory.CreateDirectory(destDir);
        foreach (var file in Directory.GetFiles(sourceDir))
        {
            var destFile = Path.Combine(destDir, Path.GetFileName(file));
            File.Copy(file, destFile, overwrite: true);
        }
        foreach (var dir in Directory.GetDirectories(sourceDir))
        {
            var destSub = Path.Combine(destDir, Path.GetFileName(dir));
            CopyDirectory(dir, destSub);
        }
    }

    // ── Column header context menu handlers ──────────────────────────────────

    private void ColumnHeader_ContextMenuOpening(object sender, ContextMenuEventArgs e)
    {
        if (sender is not DataGridColumnHeader header)
            return;

        _activeHeader = header;
        _activeGrid = FindParentDataGrid(header);

        // Rebuild menu every time so Edit/Delete are only shown for dynamic columns
        bool isDynamic = header.Column is IDynamicColumn;

        var menu = new ContextMenu();

        if (isDynamic)
        {
            var editItem = new MenuItem { Header = "Edit Column…" };
            editItem.Click += ColumnHeader_Edit_Click;
            menu.Items.Add(editItem);
        }
        else
        {
            var editItem = new MenuItem { Header = "Edit Header" };
            editItem.Click += ColumnHeader_Edit_Click;
            menu.Items.Add(editItem);
        }

        var addItem = new MenuItem { Header = "Add Column (after)…" };
        addItem.Click += ColumnHeader_Add_Click;
        menu.Items.Add(addItem);

        if (isDynamic)
        {
            var deleteItem = new MenuItem { Header = "Delete Column" };
            deleteItem.Click += ColumnHeader_Delete_Click;
            menu.Items.Add(deleteItem);
        }

        if (isDynamic && header.Column is IDynamicColumn dynHdrCol && dynHdrCol.DefinitionKind == DataKind.Number)
        {
            var def = _hub.Columns.GetAll().FirstOrDefault(c => c.Id == dynHdrCol.DefinitionId);
            menu.Items.Add(new Separator());
            var setThreshLabel = def?.WarningThreshold is double t ? $"📊  Column Threshold: {t:G}…" : "📊  Set Column Threshold…";
            var setThreshItem  = new MenuItem { Header = setThreshLabel };
            setThreshItem.Tag   = dynHdrCol.DefinitionId;
            setThreshItem.Click += ColumnHeader_SetThreshold_Click;
            menu.Items.Add(setThreshItem);
            if (def?.WarningThreshold is not null)
            {
                var clearThreshItem = new MenuItem { Header = "✕  Clear Column Threshold", Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0x55, 0x55)) };
                clearThreshItem.Tag    = dynHdrCol.DefinitionId;
                clearThreshItem.Click += ColumnHeader_ClearThreshold_Click;
                menu.Items.Add(clearThreshItem);
            }
        }

        // Cancel whatever menu WPF already resolved (on first click it would be the
        // DataGrid row menu because the header had no ContextMenu yet).  Open the
        // freshly-built header menu directly instead.
        e.Handled = true;
        menu.PlacementTarget = header;
        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
        menu.IsOpen = true;
    }

    private void ColumnHeader_Edit_Click(object sender, RoutedEventArgs e)
    {
        if (_activeHeader?.Column is null) return;

        // Dynamic column — persist edit
        if (_activeHeader.Column is IDynamicColumn dynCol)
        {
            var def = _hub.Columns.GetAll().FirstOrDefault(c => c.Id == dynCol.DefinitionId);
            if (def is null) return;

            var tableCols = _hub.Columns.GetAll()
                .Where(c => c.TableName.Equals(def.TableName, StringComparison.OrdinalIgnoreCase) && c.Id != def.Id)
                .ToList();
            var dlg = new DataKindSelectorDialog(this, def.HeaderText, def.DataKind, def.Options, def.Formula, tableCols);
            if (dlg.ShowDialog() != true) return;

            def.HeaderText = dlg.ResultHeaderText;
            def.DataKind   = dlg.ResultDataKind;
            def.Options    = dlg.ResultOptions;
            def.Formula    = dlg.ResultFormula;
            _ = _hub.Columns.UpsertAsync(def);

            SaveGridLayout(_activeGrid!);
            RebuildDynamicColumns(_activeGrid!, def.TableName);
            ApplyGridLayout(_activeGrid!);
            return;
        }

        // Static column — persist rename
        var current = ExtractHeaderLabel(_activeHeader.Column);
        var updated = PromptForText("Edit Header", "Header text:", current);
        if (!string.IsNullOrWhiteSpace(updated) && _activeGrid is not null)
        {
            var newLabel = updated.Trim();
            // Recover the original XAML label stored in the dict (set by AttachSortHeaders)
            var origLabel   = _staticColOrigLabel.TryGetValue(_activeHeader.Column, out var orig) ? orig : current;
            var settingsKey = $"{_activeGrid.Name}|{origLabel}";
            _settings.StaticColumnLabels[settingsKey] = newLabel;
            _settings.Save();
            var view = GetGridView(_activeGrid);
            _activeHeader.Column.Header = BuildSortHeader(newLabel, _activeHeader.Column, _activeGrid, view);
        }
    }

    private void ColumnHeader_Add_Click(object sender, RoutedEventArgs e)
    {
        if (_activeGrid is null || _activeHeader?.Column is null) return;

        var tableName = GetTableName(_activeGrid);
        if (tableName is null) return;

        // SortOrder = max existing + 1 for this table
        var existing = _hub.Columns.GetAll()
            .Where(c => c.TableName == tableName)
            .ToList();
        var dlg = new DataKindSelectorDialog(this, availableColumns: existing);
        if (dlg.ShowDialog() != true) return;

        var sortOrder = existing.Count == 0 ? 0 : existing.Max(c => c.SortOrder) + 1;

        var def = new CTHub.Models.ColumnDefinition
        {
            Id           = Guid.NewGuid().ToString(),
            TableName    = tableName,
            HeaderText   = dlg.ResultHeaderText,
            DataKind     = dlg.ResultDataKind,
            Options      = dlg.ResultOptions,
            Formula      = dlg.ResultFormula,
            SortOrder    = sortOrder,
            CreatedAtUtc = DateTime.UtcNow.ToString("o")
        };

        _ = _hub.Columns.UpsertAsync(def);
        SaveGridLayout(_activeGrid);
        RebuildDynamicColumns(_activeGrid, tableName);
        ApplyGridLayout(_activeGrid);
    }

    private void ColumnHeader_Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_activeGrid is null || _activeHeader?.Column is null) return;
        if (_activeHeader.Column is not IDynamicColumn dynCol) return;

        // If this is a BarcodeScan column, unmap all QrMappings for every value it held
        var def = _hub.Columns.GetAll().FirstOrDefault(c => c.Id == dynCol.DefinitionId);
        if (def?.DataKind == DataKind.BarcodeScan)
        {
            // Gather every unique scanned value across all entry tables for this column
            var allValues = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var ct in _hub.ChaseTactical.GetAll())
                if (!string.IsNullOrWhiteSpace(ct[def.Id])) allValues.Add(ct[def.Id]);
            foreach (var th in _hub.ToughHooks.GetAll())
                if (!string.IsNullOrWhiteSpace(th[def.Id])) allValues.Add(th[def.Id]);
            foreach (var ss in _hub.ShippingSupplys.GetAll())
                if (!string.IsNullOrWhiteSpace(ss[def.Id])) allValues.Add(ss[def.Id]);

            foreach (var v in allValues)
                UnmapQrValueFromAllEntries(v);
        }

        _ = _hub.Columns.DeleteAsync(dynCol.DefinitionId);
        _activeGrid.Columns.Remove(_activeHeader.Column);
    }

    private void ColumnHeader_SetThreshold_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuItem mi) return;
        var defId = mi.Tag as string;
        if (string.IsNullOrEmpty(defId)) return;
        var def = _hub.Columns.GetAll().FirstOrDefault(c => c.Id == defId);
        if (def is null) return;
        var current = def.WarningThreshold?.ToString("G", System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty;
        var input   = PromptForText("Column Threshold", $"Highlight cells at or below this value for \"{def.HeaderText}\":", current);
        if (input is null) return;
        input = input.Trim();
        if (!double.TryParse(input, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var val)) return;
        def.WarningThreshold = val;
        _ = _hub.Columns.UpsertAsync(def);
        if (_activeGrid is not null)
        {
            SaveGridLayout(_activeGrid);
            RebuildDynamicColumns(_activeGrid, def.TableName);
            ApplyGridLayout(_activeGrid);
        }
    }

    private void ColumnHeader_ClearThreshold_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not MenuItem mi) return;
        var defId = mi.Tag as string;
        if (string.IsNullOrEmpty(defId)) return;
        var def = _hub.Columns.GetAll().FirstOrDefault(c => c.Id == defId);
        if (def is null) return;
        def.WarningThreshold = null;
        _ = _hub.Columns.UpsertAsync(def);
        if (_activeGrid is not null)
        {
            SaveGridLayout(_activeGrid);
            RebuildDynamicColumns(_activeGrid, def.TableName);
            ApplyGridLayout(_activeGrid);
        }
    }

    // ── Dynamic column helpers ────────────────────────────────────────────────

    /// <summary>Shared interface for dynamic columns carrying ColumnDefinition metadata.</summary>
    private interface IDynamicColumn
    {
        string   DefinitionId   { get; }
        DataKind DefinitionKind { get; }
        string   HeaderText     { get; }
    }

    private sealed class DynamicDataGridTextColumn : DataGridTextColumn, IDynamicColumn
    {
        public string   DefinitionId   { get; init; } = string.Empty;
        public DataKind DefinitionKind { get; init; } = DataKind.Text;
        public string   HeaderText     { get; init; } = string.Empty;
    }

    private sealed class DynamicDataGridComboBoxColumn : DataGridComboBoxColumn, IDynamicColumn
    {
        public string   DefinitionId   { get; init; } = string.Empty;
        public DataKind DefinitionKind { get; init; } = DataKind.Text;
        public string   HeaderText     { get; init; } = string.Empty;
    }

    private sealed class FormulaMultiConverter : System.Windows.Data.IMultiValueConverter
    {
        private readonly record struct Factor(int Sign, double Multiplier);
        private readonly List<Factor> _factors;

        /// <summary>Number of source-column bindings (first N). The next N are per-row multiplier overrides.</summary>
        public int SourceCount => _factors.Count;

        public FormulaMultiConverter(string formula)
        {
            _factors = formula
                .Split(' ', StringSplitOptions.RemoveEmptyEntries)
                .Select(t =>
                {
                    var sign = t[0] == '-' ? -1 : 1;
                    var rest = t[1..];
                    var star = rest.IndexOf('*');
                    double mult;
                    if (star >= 0)
                    {
                        double.TryParse(rest[(star + 1)..],
                            System.Globalization.NumberStyles.Any,
                            System.Globalization.CultureInfo.InvariantCulture, out mult);
                        if (mult == 0) mult = 1.0;
                    }
                    else mult = 1.0;
                    return new Factor(sign, mult);
                }).ToList();
        }

        public object Convert(object[] values, Type targetType, object parameter, System.Globalization.CultureInfo culture)
        {
            int n = _factors.Count;
            double total = 0;
            for (int i = 0; i < Math.Min(values.Length, n); i++)
            {
                var raw = values[i] == System.Windows.DependencyProperty.UnsetValue ? string.Empty
                        : values[i]?.ToString() ?? string.Empty;
                if (!double.TryParse(raw, System.Globalization.NumberStyles.Any,
                    System.Globalization.CultureInfo.InvariantCulture, out var srcVal))
                    continue;

                // Use per-row multiplier override if present, otherwise column-level default
                double mult = _factors[i].Multiplier;
                if (i + n < values.Length)
                {
                    var overrideRaw = values[i + n] == System.Windows.DependencyProperty.UnsetValue ? string.Empty
                                    : values[i + n]?.ToString() ?? string.Empty;
                    if (!string.IsNullOrWhiteSpace(overrideRaw) &&
                        double.TryParse(overrideRaw, System.Globalization.NumberStyles.Any,
                            System.Globalization.CultureInfo.InvariantCulture, out var overrideVal) &&
                        overrideVal != 0)
                    {
                        mult = overrideVal;
                    }
                }

                total += _factors[i].Sign * mult * srcVal;
            }
            return total == Math.Floor(total) && total is >= long.MinValue and <= long.MaxValue
                ? ((long)total).ToString()
                : total.ToString("G", culture);
        }

        public object[] ConvertBack(object value, Type[] targetTypes, object parameter, System.Globalization.CultureInfo culture)
            => throw new NotSupportedException();
    }

    /// <summary>
    /// Shows a default multiplier value when the stored string is empty;
    /// writes the user's input back as-is on edit.
    /// </summary>
    private sealed class DefaultIfEmptyConverter : System.Windows.Data.IValueConverter
    {
        private readonly string _defaultText;
        public DefaultIfEmptyConverter(double defaultValue)
            => _defaultText = defaultValue.ToString("G", System.Globalization.CultureInfo.InvariantCulture);

        public object Convert(object value, Type targetType, object parameter, System.Globalization.CultureInfo culture)
        {
            var s = value?.ToString() ?? string.Empty;
            return string.IsNullOrWhiteSpace(s) ? _defaultText : s;
        }

        public object ConvertBack(object value, Type targetType, object parameter, System.Globalization.CultureInfo culture)
            => value?.ToString() ?? string.Empty;
    }

    private sealed class ThresholdBrushConverter : System.Windows.Data.IMultiValueConverter
    {
        private static readonly SolidColorBrush _critical = (SolidColorBrush)Freeze(new SolidColorBrush(Color.FromRgb(0x5C, 0x1A, 0x1A)));
        private static readonly SolidColorBrush _warning  = (SolidColorBrush)Freeze(new SolidColorBrush(Color.FromRgb(0x4A, 0x34, 0x00)));
        private static readonly SolidColorBrush _ok       = (SolidColorBrush)Freeze(new SolidColorBrush(Colors.Transparent));

        public object Convert(object[] values, Type targetType, object parameter, System.Globalization.CultureInfo culture)
        {
            double? threshold = parameter is double d ? d : (double?)null;
            if (values.Length >= 2)
            {
                var rowStr = values[1] == DependencyProperty.UnsetValue ? string.Empty : values[1]?.ToString() ?? string.Empty;
                if (rowStr.Length > 0 && double.TryParse(rowStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var rowT))
                    threshold = rowT;
            }
            if (threshold is null) return _ok;
            var raw = values[0] == DependencyProperty.UnsetValue ? string.Empty : values[0]?.ToString() ?? string.Empty;
            if (!double.TryParse(raw, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var cellVal)) return _ok;
            if (cellVal <= threshold.Value)        return _critical;
            if (cellVal <= threshold.Value * 1.25) return _warning;
            return _ok;
        }

        public object[] ConvertBack(object value, Type[] targetTypes, object parameter, System.Globalization.CultureInfo culture)
            => throw new NotSupportedException();
    }

    private static DataGridLength DynColWidth(CTHub.Models.ColumnDefinition def) =>
        def.DefaultWidth < 0 ? new DataGridLength(1, DataGridLengthUnitType.Star) :
        def.DefaultWidth > 0 ? new DataGridLength(def.DefaultWidth) :
                                new DataGridLength(140);

    private Style BuildThresholdCellStyle(CTHub.Models.ColumnDefinition def)
    {
        var bindPath = !string.IsNullOrEmpty(def.BindingPath) ? def.BindingPath : $"[{def.Id}]";
        var rowKey   = $"[_rowThreshold_{def.Id}]";

        var bgBinding = new System.Windows.Data.MultiBinding
        {
            Converter          = new ThresholdBrushConverter(),
            ConverterParameter = def.WarningThreshold
        };
        bgBinding.Bindings.Add(new System.Windows.Data.Binding(bindPath));
        bgBinding.Bindings.Add(new System.Windows.Data.Binding(rowKey));

        var setRowItem   = new MenuItem { Header = "📊  Set Row Threshold…" };
        var clearRowItem = new MenuItem { Header = "✕  Clear Row Threshold", Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0x55, 0x55)) };
        setRowItem.Click   += NumberCell_SetRowThreshold;
        clearRowItem.Click += NumberCell_ClearRowThreshold;

        var ctxMenu = new ContextMenu();
        ctxMenu.Items.Add(setRowItem);
        ctxMenu.Items.Add(new Separator());
        ctxMenu.Items.Add(clearRowItem);

        var cellStyle = new Style(typeof(DataGridCell));
        cellStyle.Setters.Add(new Setter(DataGridCell.BackgroundProperty, bgBinding));
        cellStyle.Setters.Add(new Setter(FrameworkElement.ContextMenuProperty, ctxMenu));
        return cellStyle;
    }

    private void SeedColumnsIfNeeded()
    {
        var appliedIds = _settings.AppliedSeedIds;
        void Seed(CTHub.Models.ColumnDefinition d)
        {
            if (appliedIds.Contains(d.Id)) return;
            _ = _hub.Columns.UpsertAsync(d);
            appliedIds.Add(d.Id);
        }

        int s = 0;

        // ── Chase Tactical ────────────────────────────────────────────────
        Seed(new() { Id = "seed-ct-bin", TableName = "chasetactical",   HeaderText = "Bin",             DataKind = DataKind.Dropdown, BindingPath = "Bin",            DefaultWidth = 130,  SortOrder = s++, Options = BinLocations });
        Seed(new() { Id = "seed-ct-cls", TableName = "chasetactical",   HeaderText = "Class",           DataKind = DataKind.Dropdown, BindingPath = "ClassName",      DefaultWidth = 220,  SortOrder = s++, Options = ClassNames });
        Seed(new() { Id = "seed-ct-ltr", TableName = "chasetactical",   HeaderText = "Letter",          DataKind = DataKind.Dropdown, BindingPath = "ClassLetter",    DefaultWidth = 80,   SortOrder = s++, Options = ClassLetters });
        Seed(new() { Id = "seed-ct-cid", TableName = "chasetactical",   HeaderText = "Class ID",        DataKind = DataKind.Text,     BindingPath = "ClassId",        DefaultWidth = 180,  SortOrder = s++, IsReadOnly = true });
        Seed(new() { Id = "seed-ct-lbl", TableName = "chasetactical",   HeaderText = "Label",           DataKind = DataKind.Text,     BindingPath = "Label",          DefaultWidth = 200,  SortOrder = s++ });
        Seed(new() { Id = "seed-ct-qty", TableName = "chasetactical",   HeaderText = "Qty",             DataKind = DataKind.Number,   BindingPath = "Qty",            DefaultWidth = 80,   SortOrder = s++ });
        Seed(new() { Id = "seed-ct-stk", TableName = "chasetactical",   HeaderText = "Stock Threshold", DataKind = DataKind.Number,   BindingPath = "StockThreshold", DefaultWidth = 130,  SortOrder = s++ });
        Seed(new() { Id = "seed-ct-nts", TableName = "chasetactical",   HeaderText = "Notes",           DataKind = DataKind.Text,     BindingPath = "Notes",          DefaultWidth = -1,   SortOrder = s++ });
        Seed(new() { Id = "seed-ct-id",  TableName = "chasetactical",   HeaderText = "ID",              DataKind = DataKind.Text,     BindingPath = "Id",             DefaultWidth = 220,  SortOrder = s++, IsReadOnly = true, IsCollapsibleId = true });

        // ── Tough Hooks ───────────────────────────────────────────────────
        s = 0;
        Seed(new() { Id = "seed-th-bin", TableName = "toughhooks",      HeaderText = "Bin",             DataKind = DataKind.Text,     BindingPath = "Bin",            DefaultWidth = 120,  SortOrder = s++ });
        Seed(new() { Id = "seed-th-sku", TableName = "toughhooks",      HeaderText = "SKU",             DataKind = DataKind.Text,     BindingPath = "Sku",            DefaultWidth = 140,  SortOrder = s++ });
        Seed(new() { Id = "seed-th-dsc", TableName = "toughhooks",      HeaderText = "Description",     DataKind = DataKind.Text,     BindingPath = "Description",    DefaultWidth = -1,   SortOrder = s++ });
        Seed(new() { Id = "seed-th-qty", TableName = "toughhooks",      HeaderText = "Qty",             DataKind = DataKind.Number,   BindingPath = "Qty",            DefaultWidth = 80,   SortOrder = s++ });
        Seed(new() { Id = "seed-th-stk", TableName = "toughhooks",      HeaderText = "Stock Threshold", DataKind = DataKind.Number,   BindingPath = "StockThreshold", DefaultWidth = 130,  SortOrder = s++ });
        Seed(new() { Id = "seed-th-id",  TableName = "toughhooks",      HeaderText = "ID",              DataKind = DataKind.Text,     BindingPath = "Id",             DefaultWidth = 220,  SortOrder = s++, IsReadOnly = true, IsCollapsibleId = true });

        // ── Shipping Supplies ─────────────────────────────────────────────
        s = 0;
        Seed(new() { Id = "seed-ss-dim", TableName = "shippingsupplys", HeaderText = "Dimensions",      DataKind = DataKind.Text,     BindingPath = "Dimensions",     DefaultWidth = -1,   SortOrder = s++ });
        Seed(new() { Id = "seed-ss-bdl", TableName = "shippingsupplys", HeaderText = "Bundle",          DataKind = DataKind.Number,   BindingPath = "Bundle",         DefaultWidth = 120,  SortOrder = s++ });
        Seed(new() { Id = "seed-ss-sng", TableName = "shippingsupplys", HeaderText = "Single",          DataKind = DataKind.Number,   BindingPath = "Single",         DefaultWidth = 120,  SortOrder = s++ });
        Seed(new() { Id = "seed-ss-stk", TableName = "shippingsupplys", HeaderText = "Stock Threshold", DataKind = DataKind.Number,   BindingPath = "StockThreshold", DefaultWidth = 130,  SortOrder = s++ });
        Seed(new() { Id = "seed-ss-id",  TableName = "shippingsupplys", HeaderText = "ID",              DataKind = DataKind.Text,     BindingPath = "Id",             DefaultWidth = 220,  SortOrder = s++, IsReadOnly = true, IsCollapsibleId = true });

        // ── QR / Code Mappings ────────────────────────────────────────────
        s = 0;
        Seed(new() { Id = "seed-qr-val", TableName = "qrmappings", HeaderText = "QR Value",      DataKind = DataKind.Text, BindingPath = "QrValue",        DefaultWidth = 220,  SortOrder = s++ });
        Seed(new() { Id = "seed-qr-cls", TableName = "qrmappings", HeaderText = "Classification", DataKind = DataKind.Text, BindingPath = "Classification", DefaultWidth = 180,  SortOrder = s++ });
        Seed(new() { Id = "seed-qr-dsc", TableName = "qrmappings", HeaderText = "Description",   DataKind = DataKind.Text, BindingPath = "Description",    DefaultWidth = -1,   SortOrder = s++ });
        Seed(new() { Id = "seed-qr-id",  TableName = "qrmappings", HeaderText = "ID",            DataKind = DataKind.Text, BindingPath = "Id",             DefaultWidth = 220,  SortOrder = s++, IsReadOnly = true, IsCollapsibleId = true });

        // ── Seed default mobile card config ───────────────────────────────
        var cfg = _settings.MobileCardConfig;
        if (!cfg.ContainsKey("chasetactical"))
            cfg["chasetactical"] = new CTHub.Services.MobileCardEntry
                { Row1 = "Label", Row2 = new() { "Bin", "ClassName" }, Badge = "Qty" };
        if (!cfg.ContainsKey("toughhooks"))
            cfg["toughhooks"] = new CTHub.Services.MobileCardEntry
                { Row1 = "Sku", Row2 = new() { "Bin" }, Badge = "Qty" };
        if (!cfg.ContainsKey("shippingsupplys"))
            cfg["shippingsupplys"] = new CTHub.Services.MobileCardEntry
                { Row1 = "Dimensions", Row2 = new() { "Bundle", "Single" }, Badge = null };

        _settings.Save();
    }

    private void RebuildAllDynamicColumns()
    {
        RebuildDynamicColumns(ChaseTacticalGrid,   "chasetactical");
        RebuildDynamicColumns(ToughHooksGrid,      "toughhooks");
        RebuildDynamicColumns(ShippingSupplysGrid, "shippingsupplys");
        RebuildDynamicColumns(QrMappingsGrid,      "qrmappings");
    }

    private void RebuildDynamicColumns(DataGrid grid, string tableName)
    {
        // Remove existing dynamic columns
        var toRemove = grid.Columns.Where(c => c is IDynamicColumn).ToList();
        foreach (var col in toRemove)
            grid.Columns.Remove(col);

        // Re-insert in SortOrder
        var defs = _hub.Columns.GetAll()
            .Where(c => c.TableName.Equals(tableName, StringComparison.OrdinalIgnoreCase))
            .OrderBy(c => c.SortOrder);

        var allDefsCache = _hub.Columns.GetAll().ToList();
        foreach (var def in defs)
        {
            // Computed column — MultiBinding on each source property for live updates
            if (def.DataKind == DataKind.Computed && !string.IsNullOrEmpty(def.Formula))
            {
                var defMap = allDefsCache.ToDictionary(d => d.Id);
                var formulaConverter = new FormulaMultiConverter(def.Formula);
                var mb = new System.Windows.Data.MultiBinding
                {
                    Converter = formulaConverter,
                    Mode      = System.Windows.Data.BindingMode.OneWay
                };

                // Parse formula terms for source bindings and per-row override info
                var formulaTerms = def.Formula.Split(' ', StringSplitOptions.RemoveEmptyEntries);

                // First N bindings: source column values
                foreach (var token in formulaTerms)
                {
                    var rest  = token[1..];
                    var star  = rest.IndexOf('*');
                    var colId = star >= 0 ? rest[..star] : rest;
                    var bp    = defMap.TryGetValue(colId, out var d) && !string.IsNullOrEmpty(d.BindingPath)
                                ? d.BindingPath
                                : $"[{colId}]";
                    mb.Bindings.Add(new System.Windows.Data.Binding(bp));
                }

                // Next N bindings: per-row multiplier overrides (stored in ExtraFields)
                for (int ti = 0; ti < formulaTerms.Length; ti++)
                {
                    var overrideKey = $"_rowMult_{def.Id}_{ti}";
                    mb.Bindings.Add(new System.Windows.Data.Binding($"[{overrideKey}]"));
                }

                var tc = new DynamicDataGridTextColumn
                {
                    DefinitionId   = def.Id,
                    DefinitionKind = def.DataKind,
                    HeaderText     = def.HeaderText,
                    Header         = BuildColumnHeader(def),
                    Binding        = mb,
                    Width          = DynColWidth(def),
                    IsReadOnly     = true
                };
                var computedCellStyle = new Style(typeof(TextBlock));
                computedCellStyle.Setters.Add(new Setter(TextBlock.ForegroundProperty,
                    new SolidColorBrush(Color.FromRgb(0xD4, 0xD4, 0xD4))));
                tc.ElementStyle = computedCellStyle;
                grid.Columns.Add(tc);

                // Add editable companion columns for per-row multiplier overrides
                // (only for terms whose column-level multiplier is not 1.0)
                for (int ti = 0; ti < formulaTerms.Length; ti++)
                {
                    var termToken = formulaTerms[ti];
                    var termRest  = termToken[1..];
                    var termStar  = termRest.IndexOf('*');
                    double termMult = 1.0;
                    if (termStar >= 0)
                    {
                        double.TryParse(termRest[(termStar + 1)..],
                            System.Globalization.NumberStyles.Any,
                            System.Globalization.CultureInfo.InvariantCulture, out termMult);
                        if (termMult == 0) termMult = 1.0;
                    }
                    if (termMult == 1.0) continue;

                    var overrideKey = $"_rowMult_{def.Id}_{ti}";
                    var companion = new DynamicDataGridTextColumn
                    {
                        DefinitionId   = $"{def.Id}__rowmult_{ti}",
                        DefinitionKind = DataKind.Number,
                        HeaderText     = $"{def.HeaderText} ×",
                        Header         = $"{def.HeaderText} ×",
                        Binding        = new System.Windows.Data.Binding($"[{overrideKey}]")
                        {
                            Converter           = new DefaultIfEmptyConverter(termMult),
                            UpdateSourceTrigger = System.Windows.Data.UpdateSourceTrigger.PropertyChanged
                        },
                        Width    = new DataGridLength(90),
                        IsReadOnly = false
                    };
                    grid.Columns.Add(companion);
                }

                continue;
            }

            var bindPath = !string.IsNullOrEmpty(def.BindingPath) ? def.BindingPath : $"[{def.Id}]";

            DataGridColumn col;
            if (def.DataKind == DataKind.Dropdown)
            {
                col = new DynamicDataGridComboBoxColumn
                {
                    DefinitionId        = def.Id,
                    DefinitionKind      = def.DataKind,
                    HeaderText          = def.HeaderText,
                    Header              = BuildColumnHeader(def),
                    SelectedItemBinding = new System.Windows.Data.Binding(bindPath)
                    {
                        UpdateSourceTrigger = System.Windows.Data.UpdateSourceTrigger.PropertyChanged
                    },
                    ItemsSource         = def.Options ?? [],
                    Width               = DynColWidth(def)
                };
            }
            else
            {
                var tc = new DynamicDataGridTextColumn
                {
                    DefinitionId   = def.Id,
                    DefinitionKind = def.DataKind,
                    HeaderText     = def.HeaderText,
                    Header         = BuildColumnHeader(def),
                    Binding        = new System.Windows.Data.Binding(bindPath),
                    Width          = DynColWidth(def)
                };
                if (def.IsReadOnly) tc.IsReadOnly = true;
                if (def.IsCollapsibleId)
                {
                    var idStyle = new Style(typeof(TextBlock));
                    idStyle.Setters.Add(new Setter(TextBlock.ForegroundProperty, new SolidColorBrush(Color.FromRgb(0x55, 0x55, 0x55))));
                    idStyle.Setters.Add(new Setter(TextBlock.FontSizeProperty, 10.0));
                    tc.ElementStyle = idStyle;
                }
                col = tc;
            }

            if (!string.IsNullOrEmpty(def.BindingPath))
                col.SortMemberPath = def.BindingPath;

            if (def.DataKind == DataKind.BarcodeScan)
            {
                col.IsReadOnly = true;

                var editItem   = new MenuItem { Header = "✏  Edit value" };
                var clearItem  = new MenuItem { Header = "✕  Clear", Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0x55, 0x55)) };
                var linksItem  = new MenuItem { Header = "🔗  Manage links…" };
                editItem.Click  += BarcodeCell_Edit;
                clearItem.Click += BarcodeCell_Clear;
                linksItem.Click += BarcodeCell_ManageLinks;

                var menu = new ContextMenu();
                menu.Items.Add(editItem);
                menu.Items.Add(linksItem);
                menu.Items.Add(new Separator());
                menu.Items.Add(clearItem);

                var cellStyle = new Style(typeof(DataGridCell));
                cellStyle.Setters.Add(new Setter(FrameworkElement.ContextMenuProperty, menu));
                col.CellStyle = cellStyle;
            }

            if (def.DataKind == DataKind.Number)
                col.CellStyle = BuildThresholdCellStyle(def);

            grid.Columns.Add(col);
        }

        AttachSortHeaders(grid);
    }

    private static FrameworkElement BuildColumnHeader(CTHub.Models.ColumnDefinition def)
    {
        var badge = new TextBlock
        {
            Text              = DataKindBadge(def.DataKind),
            FontSize          = 10,
            Foreground        = new SolidColorBrush(Color.FromRgb(0x85, 0x85, 0x85)),
            Margin            = new Thickness(4, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };

        var title = new TextBlock
        {
            Text              = def.HeaderText,
            VerticalAlignment = VerticalAlignment.Center
        };

        return new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Children    = { title, badge }
        };
    }

    // ── Sort headers ──────────────────────────────────────────────────────────

    private readonly Dictionary<DataGridColumn, ListSortDirection?> _colSortStates = new();

    // Per-grid: the currently-active column's up/down arrows so we can reset them
    private readonly Dictionary<DataGrid, (DataGridColumn col, System.Windows.Shapes.Path up, System.Windows.Shapes.Path down)> _activeSortCol = new();
    // Original XAML label for static columns — key for StaticColumnLabels lookups
    private readonly Dictionary<DataGridColumn, string> _staticColOrigLabel = new();

    private static ControlTemplate? _sortBtnTemplate;
    private static ControlTemplate SortBtnTemplate => _sortBtnTemplate ??= CreateSortBtnTemplate();

    private static ControlTemplate CreateSortBtnTemplate()
    {
        var t  = new ControlTemplate(typeof(Button));
        var cp = new FrameworkElementFactory(typeof(ContentPresenter));
        cp.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        cp.SetValue(ContentPresenter.VerticalAlignmentProperty,   VerticalAlignment.Center);
        t.VisualTree = cp;
        t.Seal();
        return t;
    }

    private static readonly SolidColorBrush _sortOrange = (SolidColorBrush)Freeze(new SolidColorBrush(Color.FromRgb(0xFF, 0x95, 0x00)));
    private static readonly SolidColorBrush _sortGrey   = (SolidColorBrush)Freeze(new SolidColorBrush(Color.FromRgb(0x60, 0x60, 0x60)));

    private static System.Windows.Shapes.Path MakeSortArrow(bool up)
    {
        // Solid triangle pointing up or down
        var geo = Geometry.Parse(up ? "M 4,0 L 8,7 L 0,7 Z" : "M 4,7 L 8,0 L 0,0 Z");
        geo.Freeze();
        return new System.Windows.Shapes.Path
        {
            Data                = geo,
            Fill                = _sortGrey,
            Width               = 9,
            Height              = 7,
            Stretch             = Stretch.Uniform,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment   = VerticalAlignment.Center,
        };
    }

    private void AttachSortHeaders(DataGrid grid)
    {
        var view = GetGridView(grid);
        foreach (var col in grid.Columns)
        {
            if (col.Header is FrameworkElement fh && "sort-header".Equals(fh.Tag))
                continue;
            // For static columns, check if the user previously renamed it
            string label;
            if (col is not IDynamicColumn)
            {
                var origLabel   = ExtractHeaderLabel(col);
                var settingsKey = $"{grid.Name}|{origLabel}";
                label = _settings.StaticColumnLabels.TryGetValue(settingsKey, out var saved)
                    ? saved
                    : origLabel;
                // Stash the original XAML label so rename can key off it
                _staticColOrigLabel[col] = origLabel;
            }
            else
            {
                label = ExtractHeaderLabel(col);
            }
            col.Header = BuildSortHeader(label, col, grid, view);
        }
        PinIdColumnLast(grid);
    }

    private static string ExtractHeaderLabel(DataGridColumn col) => col.Header switch
    {
        string s            => s,
        FrameworkElement fe => ExtractLabelFromElement(fe),
        _                   => col.Header?.ToString() ?? string.Empty
    };

    private static string ExtractLabelFromElement(FrameworkElement fe)
    {
        // DockPanel = sort header wrapper: label content is the LastChildFill (last) child
        if (fe is DockPanel dp && dp.Children.Count >= 2)
        {
            var last = dp.Children[dp.Children.Count - 1];
            if (last is TextBlock tb0) return tb0.Text;
            if (last is StackPanel sp0 && sp0.Children.Count > 0 && sp0.Children[0] is TextBlock tb1) return tb1.Text;
        }
        if (fe is StackPanel sp && sp.Children.Count > 0 && sp.Children[0] is TextBlock tb)
            return tb.Text;
        return string.Empty;
    }

    private FrameworkElement BuildSortHeader(string label, DataGridColumn col, DataGrid grid, ICollectionView? view)
    {
        var sortPath = GetSortPath(col);

        var upArrow   = MakeSortArrow(up: true);
        var downArrow = MakeSortArrow(up: false);

        var sortBtn = new Button
        {
            Content = new StackPanel
            {
                Orientation       = Orientation.Vertical,
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
                Width             = 12,
                Children          = { upArrow, new Border { Height = 3 }, downArrow }
            },
            Template          = SortBtnTemplate,
            Padding           = new Thickness(0),
            Margin            = new Thickness(4, 0, 4, 0),
            Cursor            = System.Windows.Input.Cursors.Hand,
            VerticalAlignment = VerticalAlignment.Stretch,
            ToolTip           = "Sort",
        };

        sortBtn.Click += (_, args) =>
        {
            args.Handled = true;
            if (string.IsNullOrEmpty(sortPath)) return;

            // Reset the previously-active column in this grid
            if (_activeSortCol.TryGetValue(grid, out var prev) && !ReferenceEquals(prev.col, col))
            {
                _colSortStates[prev.col] = null;
                prev.up.Fill   = _sortGrey;
                prev.down.Fill = _sortGrey;
            }

            var current = _colSortStates.TryGetValue(col, out var s) ? s : null;
            var next = current switch
            {
                null                        => (ListSortDirection?)ListSortDirection.Ascending,
                ListSortDirection.Ascending => ListSortDirection.Descending,
                _                           => null
            };
            _colSortStates[col] = next;

            if (next.HasValue)
                _activeSortCol[grid] = (col, upArrow, downArrow);
            else
                _activeSortCol.Remove(grid);

            if (view is not null)
            {
                view.SortDescriptions.Clear();
                if (next.HasValue)
                    view.SortDescriptions.Add(new SortDescription(sortPath, next.Value));
            }

            upArrow.Fill   = next == ListSortDirection.Ascending  ? _sortOrange : _sortGrey;
            downArrow.Fill = next == ListSortDirection.Descending ? _sortOrange : _sortGrey;
        };

        var labelBlock = new TextBlock
        {
            Text              = label,
            VerticalAlignment = VerticalAlignment.Center,
        };

        FrameworkElement labelContent;
        if (col is IDynamicColumn dyn)
        {
            var badgeBlock = new TextBlock
            {
                Text              = DataKindBadge(dyn.DefinitionKind),
                FontSize          = 10,
                Foreground        = new SolidColorBrush(Color.FromRgb(0x85, 0x85, 0x85)),
                Margin            = new Thickness(4, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            labelContent = new StackPanel
            {
                Orientation       = Orientation.Horizontal,
                VerticalAlignment = VerticalAlignment.Center,
                Children          = { labelBlock, badgeBlock }
            };
        }
        else
        {
            labelContent = labelBlock;
        }

        var panel = new DockPanel
        {
            Tag               = "sort-header",
            LastChildFill     = true,
            VerticalAlignment = VerticalAlignment.Stretch,
        };
        DockPanel.SetDock(sortBtn, Dock.Right);
        panel.Children.Add(sortBtn);
        panel.Children.Add(labelContent);
        return panel;
    }

    private FrameworkElement BuildIdColHeader(DataGridColumn col, DataGrid grid) => throw new NotImplementedException(); // removed — handled by overlay button

    private void IdColToggle_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button btn || btn.Tag is not string gridName) return;
        var grid = AllDataGrids.FirstOrDefault(g => g.Name == gridName);
        if (grid is null) return;
        var idCol = grid.Columns.FirstOrDefault(c => GetSortPath(c) == "Id");
        if (idCol is null) return;

        var nowHidden = idCol.Visibility == Visibility.Collapsed;
        idCol.Visibility = nowHidden ? Visibility.Visible : Visibility.Collapsed;
        btn.Content = nowHidden ? "\u25C1" : "\u25B7";  // ◁ / ▷
    }

    private void PinIdColumnLast(DataGrid grid)
    {
        var idCol = grid.Columns.FirstOrDefault(c => GetSortPath(c) == "Id");
        if (idCol is null) return;
        var maxIdx = grid.Columns.Max(c => c.DisplayIndex);
        if (idCol.DisplayIndex != maxIdx)
        {
            try { idCol.DisplayIndex = maxIdx; }
            catch { }
        }
    }

    private static string GetSortPath(DataGridColumn col)
    {
        if (!string.IsNullOrEmpty(col.SortMemberPath))
            return col.SortMemberPath;
        if (col is DataGridBoundColumn bc && bc.Binding is System.Windows.Data.Binding b)
            return b.Path.Path;
        if (col is DataGridComboBoxColumn cbc && cbc.SelectedItemBinding is System.Windows.Data.Binding sb)
            return sb.Path.Path;
        return string.Empty;
    }

    private ICollectionView? GetGridView(DataGrid grid) => grid.Name switch
    {
        "ChaseTacticalGrid"   => _chaseView,
        "ToughHooksGrid"      => _toughHooksView,
        "ShippingSupplysGrid" => _shippingSupplysView,
        "QrMappingsGrid"      => _qrMappingsView,
        _                     => null
    };

    // ── Grid column layout persistence ─────────────────────────────────────────────────

    private DataGrid[] AllDataGrids => [ChaseTacticalGrid, ToughHooksGrid, ShippingSupplysGrid, QrMappingsGrid];

    private void SaveGridLayout(DataGrid grid)
    {
        _settings.ColumnLayouts[grid.Name] = grid.Columns
            .Select(col => new ColumnLayoutEntry
            {
                Key          = ColumnKey(col),
                Width        = col.Width.UnitType == DataGridLengthUnitType.Pixel ? col.Width.Value : double.NaN,
                DisplayIndex = col.DisplayIndex
            })
            .ToList();
        _settings.Save();
    }

    private void SaveAllGridLayouts()
    {
        foreach (var grid in AllDataGrids)
            SaveGridLayout(grid);
    }

    private void ApplyAllGridLayouts()
    {
        // One-time cleanup: if any layout was saved with the old broken DockPanel key, wipe it
        // so it doesn't silently block legitimate saves from being applied.
        bool purged = false;
        foreach (var grid in AllDataGrids)
        {
            if (_settings.ColumnLayouts.TryGetValue(grid.Name, out var entries)
                && entries.Any(e => e.Key.Contains("DockPanel") || string.IsNullOrEmpty(e.Key)))
            {
                _settings.ColumnLayouts.Remove(grid.Name);
                purged = true;
            }
        }
        if (purged) _settings.Save();

        foreach (var grid in AllDataGrids)
            ApplyGridLayout(grid);
        foreach (var grid in AllDataGrids)
            PinIdColumnLast(grid);
    }

    private void ApplyGridLayout(DataGrid grid)
    {
        if (!_settings.ColumnLayouts.TryGetValue(grid.Name, out var entries) || entries.Count == 0)
            return;

        var byKey = entries.ToDictionary(e => e.Key);

        // Apply widths first (order-independent)
        foreach (var col in grid.Columns)
        {
            if (byKey.TryGetValue(ColumnKey(col), out var entry) && !double.IsNaN(entry.Width) && entry.Width > 0)
                col.Width = new DataGridLength(entry.Width);
        }

        // Apply display indexes in ascending order to avoid WPF range violations
        var ordered = entries
            .OrderBy(e => e.DisplayIndex)
            .ToList();

        foreach (var entry in ordered)
        {
            var col = grid.Columns.FirstOrDefault(c => ColumnKey(c) == entry.Key);
            if (col is null) continue;
            var clamped = Math.Clamp(entry.DisplayIndex, 0, grid.Columns.Count - 1);
            if (col.DisplayIndex != clamped)
            {
                try { col.DisplayIndex = clamped; }
                catch { /* ignore if reorder not supported */ }
            }
        }
    }

    private static string ColumnKey(DataGridColumn col) => col switch
    {
        IDynamicColumn dyn => dyn.DefinitionId,
        _                  => ExtractHeaderLabel(col)
    };

    // ── Barcode cell context menu handlers ─────────────────────────────────

    private void BarcodeCell_Edit(object sender, RoutedEventArgs e)
    {
        if (!TryGetBarcodeCellTarget(sender, out var grid, out var col, out var rowItem)) return;
        var current = GetExtraFieldValue(rowItem!, col!.DefinitionId);
        var newVal  = PromptForText($"Edit — {col.HeaderText}", "Barcode / QR value:", current);
        if (newVal is null) return;
        SetAndUpsertExtraField(grid!, rowItem!, col.DefinitionId, newVal);
    }

    private void BarcodeCell_Clear(object sender, RoutedEventArgs e)
    {
        if (!TryGetBarcodeCellTarget(sender, out var grid, out var col, out var rowItem)) return;

        var barcodeValue = GetExtraFieldValue(rowItem!, col!.DefinitionId);
        var orphanedLinks = string.IsNullOrWhiteSpace(barcodeValue)
            ? []
            : _hub.BarcodeLinks.GetAll()
                .Where(l => l.SourceBarcodeValue.Equals(barcodeValue, StringComparison.OrdinalIgnoreCase)
                         && l.SourceColumnId == col.DefinitionId)
                .ToList();

        var linkWarning = orphanedLinks.Count > 0
            ? $"\n\nThis will also remove {orphanedLinks.Count} associated link{(orphanedLinks.Count == 1 ? "" : "s")}."
            : string.Empty;

        var confirm = MessageBox.Show(
            $"Clear the barcode value for column \"{col.HeaderText}\"?{linkWarning}",
            "CT Hub", MessageBoxButton.OKCancel, MessageBoxImage.Question);
        if (confirm != MessageBoxResult.OK) return;

        foreach (var link in orphanedLinks)
            _ = _hub.BarcodeLinks.DeleteAsync(link.Id);

        // Remove any QrClassMapping whose QrValue matches the cleared barcode
        foreach (var mapping in _hub.QrMappings.GetAll()
            .Where(m => m.QrValue.Equals(barcodeValue, StringComparison.OrdinalIgnoreCase)).ToList())
            _ = _hub.QrMappings.DeleteAsync(mapping.Id);

        SetAndUpsertExtraField(grid!, rowItem!, col.DefinitionId, string.Empty);
    }

    private void BarcodeCell_ManageLinks(object sender, RoutedEventArgs e)
    {
        if (!TryGetBarcodeCellTarget(sender, out _, out var col, out var rowItem)) return;
        var barcodeValue = GetExtraFieldValue(rowItem!, col!.DefinitionId);
        if (string.IsNullOrWhiteSpace(barcodeValue))
        {
            MessageBox.Show(
                "This cell has no barcode value yet. Edit it first before adding links.",
                "CT Hub", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var tableName = rowItem switch
        {
            ChaseTacticalEntry  => "chasetactical",
            ToughHookEntry      => "toughhooks",
            ShippingSupplyEntry => "shippingsupplys",
            _                   => string.Empty
        };
        new BarcodeLinkDialog(this, _hub, barcodeValue, col.DefinitionId, tableName).ShowDialog();
    }

    private static bool TryGetBarcodeCellTarget(
        object sender,
        out DataGrid? grid,
        out DynamicDataGridTextColumn? col,
        out object? rowItem)
    {
        grid = null; col = null; rowItem = null;
        if (sender is not MenuItem mi) return false;
        if (mi.Parent is not ContextMenu cm) return false;
        if (cm.PlacementTarget is not DataGridCell cell) return false;
        col     = cell.Column as DynamicDataGridTextColumn;
        grid    = FindParentDataGrid(cell);
        rowItem = cell.DataContext;
        return col is not null && grid is not null && rowItem is not null;
    }

    private static bool TryGetNumberCellTarget(
        object sender,
        out DataGrid? grid,
        out DynamicDataGridTextColumn? col,
        out object? rowItem)
    {
        grid = null; col = null; rowItem = null;
        if (sender is not MenuItem mi) return false;
        if (mi.Parent is not ContextMenu cm) return false;
        if (cm.PlacementTarget is not DataGridCell cell) return false;
        col     = cell.Column as DynamicDataGridTextColumn;
        grid    = FindParentDataGrid(cell);
        rowItem = cell.DataContext;
        return col?.DefinitionKind == DataKind.Number && grid is not null && rowItem is not null;
    }

    private void NumberCell_SetRowThreshold(object sender, RoutedEventArgs e)
    {
        if (!TryGetNumberCellTarget(sender, out var grid, out var col, out var rowItem)) return;
        var rowKey  = $"_rowThreshold_{col!.DefinitionId}";
        var current = GetExtraFieldValue(rowItem!, rowKey);
        var input   = PromptForText("Row Threshold", $"Override threshold for this row in \"{col.HeaderText}\":", current);
        if (input is null) return;
        input = input.Trim();
        if (!double.TryParse(input, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out _)) return;
        SetAndUpsertExtraField(grid!, rowItem!, rowKey, input);
    }

    private void NumberCell_ClearRowThreshold(object sender, RoutedEventArgs e)
    {
        if (!TryGetNumberCellTarget(sender, out var grid, out var col, out var rowItem)) return;
        var rowKey = $"_rowThreshold_{col!.DefinitionId}";
        SetAndUpsertExtraField(grid!, rowItem!, rowKey, string.Empty);
    }

    private static string GetExtraFieldValue(object rowItem, string defId) => rowItem switch
    {
        ChaseTacticalEntry  ct => ct[defId],
        ToughHookEntry      th => th[defId],
        ShippingSupplyEntry ss => ss[defId],
        _                      => string.Empty
    };

    private void SetAndUpsertExtraField(DataGrid grid, object rowItem, string defId, string value)
    {
        switch (rowItem)
        {
            case ChaseTacticalEntry ct:
                ct[defId] = value;
                _ = _hub.ChaseTactical.UpsertAsync(ct);
                break;
            case ToughHookEntry th:
                th[defId] = value;
                _ = _hub.ToughHooks.UpsertAsync(th);
                break;
            case ShippingSupplyEntry ss:
                ss[defId] = value;
                _ = _hub.ShippingSupplys.UpsertAsync(ss);
                break;
        }

        // Force the DataGrid to re-evaluate cells for this row — needed because
        // IsReadOnly columns don't go through the normal edit commit path.
        grid.Items.Refresh();

        Touch();
    }

    private static string DataKindBadge(CTHub.Models.DataKind kind) => kind switch
    {
        CTHub.Models.DataKind.Text        => "Tt",
        CTHub.Models.DataKind.Number      => "#",
        CTHub.Models.DataKind.Dropdown    => "▾",
        CTHub.Models.DataKind.Date        => "📅",
        CTHub.Models.DataKind.BarcodeScan => "▣",
        CTHub.Models.DataKind.Photo       => "🖼",
        CTHub.Models.DataKind.Gps         => "📍",
        CTHub.Models.DataKind.ManualEntry => "✏",
        CTHub.Models.DataKind.Toggle      => "⊙",
        CTHub.Models.DataKind.Computed    => "∑",
        _                                 => "?"
    };

    /// <summary>
    /// Removes all BarcodeLinkEntries that point to (or originate from) the given
    /// entry when it is being deleted, preventing ghost links on the phone.
    /// </summary>
    private void DeleteBarcodeLinksByEntry(string tableName, string entryId)
    {
        var orphans = _hub.BarcodeLinks.GetAll()
            .Where(l => (l.TargetTableName.Equals(tableName, StringComparison.OrdinalIgnoreCase)
                         && l.TargetEntryId == entryId)
                     || (l.SourceTableName.Equals(tableName, StringComparison.OrdinalIgnoreCase)
                         && l.SourceBarcodeValue != string.Empty
                         && l.TargetEntryId == entryId))
            .ToList();

        foreach (var link in orphans)
            _ = _hub.BarcodeLinks.DeleteAsync(link.Id);
    }

    /// <summary>
    /// Clears <paramref name="qrValue"/> from every BarcodeScan extra-field that holds it
    /// and deletes all BarcodeLink rows that reference it.
    /// Call whenever a QrClassMapping is removed or its QrValue changes.
    /// </summary>
    private void UnmapQrValueFromAllEntries(string qrValue)
    {
        if (string.IsNullOrWhiteSpace(qrValue)) return;

        // Only BarcodeScan columns can legitimately hold a scanned barcode value
        var barcodeColIds = _hub.Columns.GetAll()
            .Where(c => c.DataKind == DataKind.BarcodeScan)
            .Select(c => c.Id)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        // Delete every BarcodeLink that references this value
        foreach (var link in _hub.BarcodeLinks.GetAll()
            .Where(l => l.SourceBarcodeValue.Equals(qrValue, StringComparison.OrdinalIgnoreCase)).ToList())
            _ = _hub.BarcodeLinks.DeleteAsync(link.Id);

        // Clear the value from every ChaseTactical entry that holds it in a scan column
        foreach (var entry in _hub.ChaseTactical.GetAll())
        {
            var dirty = false;
            foreach (var key in entry.ExtraFields.Keys.ToList())
            {
                if (!barcodeColIds.Contains(key)) continue;
                if (!entry.ExtraFields[key].Equals(qrValue, StringComparison.OrdinalIgnoreCase)) continue;
                entry.ExtraFields[key] = string.Empty;
                dirty = true;
            }
            if (dirty) _ = _hub.ChaseTactical.UpsertAsync(entry);
        }

        // Clear from ToughHook entries
        foreach (var entry in _hub.ToughHooks.GetAll())
        {
            var dirty = false;
            foreach (var key in entry.ExtraFields.Keys.ToList())
            {
                if (!barcodeColIds.Contains(key)) continue;
                if (!entry.ExtraFields[key].Equals(qrValue, StringComparison.OrdinalIgnoreCase)) continue;
                entry.ExtraFields[key] = string.Empty;
                dirty = true;
            }
            if (dirty) _ = _hub.ToughHooks.UpsertAsync(entry);
        }

        // Clear from ShippingSupply entries
        foreach (var entry in _hub.ShippingSupplys.GetAll())
        {
            var dirty = false;
            foreach (var key in entry.ExtraFields.Keys.ToList())
            {
                if (!barcodeColIds.Contains(key)) continue;
                if (!entry.ExtraFields[key].Equals(qrValue, StringComparison.OrdinalIgnoreCase)) continue;
                entry.ExtraFields[key] = string.Empty;
                dirty = true;
            }
            if (dirty) _ = _hub.ShippingSupplys.UpsertAsync(entry);
        }

        // Force grids to re-render the now-empty cells
        foreach (var g in AllDataGrids)
            g.Items.Refresh();
    }

    /// <summary>
    /// Collects all barcode values stored in BarcodeScan extra-fields of <paramref name="extraFields"/>
    /// and removes any QrClassMapping whose QrValue matches.
    /// Call whenever an inventory entry row is deleted.
    /// </summary>
    private void DeleteQrMappingsForEntryBarcodeValues(Dictionary<string, string> extraFields)
    {
        var barcodeColIds = _hub.Columns.GetAll()
            .Where(c => c.DataKind == DataKind.BarcodeScan)
            .Select(c => c.Id)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var values = extraFields
            .Where(kv => barcodeColIds.Contains(kv.Key) && !string.IsNullOrWhiteSpace(kv.Value))
            .Select(kv => kv.Value)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var mapping in _hub.QrMappings.GetAll()
            .Where(m => values.Contains(m.QrValue)).ToList())
            _ = _hub.QrMappings.DeleteAsync(mapping.Id);
    }

    private string? GetTableName(DataGrid grid) => grid.Name switch
    {
        "ChaseTacticalGrid"   => "chasetactical",
        "ToughHooksGrid"      => "toughhooks",
        "ShippingSupplysGrid" => "shippingsupplys",
        _                     => null
    };

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
            Label = "New item",
            StockThreshold = 0
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
            DeleteBarcodeLinksByEntry("chasetactical", item.Id);
            DeleteQrMappingsForEntryBarcodeValues(item.ExtraFields);
            _ = _hub.ChaseTactical.DeleteAsync(item.Id);
        }

        if (selected.Count > 0) Touch();
    }

    private void ChaseTactical_SetSection(object sender, RoutedEventArgs e)
    {
        var selected = ChaseTacticalGrid.SelectedItems.Cast<ChaseTacticalEntry>().ToList();
        if (selected.Count == 0) return;
        var current = selected[0].SectionLabel;
        var label = PromptForText("Set Section", "Section label for selected rows:", current);
        if (label is null) return;
        foreach (var item in selected) { item.SectionLabel = label; _ = _hub.ChaseTactical.UpsertAsync(item); }
        Touch();
        _chaseView?.Refresh();
    }

    private void ChaseTactical_ClearSection(object sender, RoutedEventArgs e)
    {
        var selected = ChaseTacticalGrid.SelectedItems.Cast<ChaseTacticalEntry>().ToList();
        foreach (var item in selected) { item.SectionLabel = string.Empty; _ = _hub.ChaseTactical.UpsertAsync(item); }
        if (selected.Count > 0) { Touch(); _chaseView?.Refresh(); }
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
        var entry = new ToughHookEntry { Bin = "—", Sku = "NEW", StockThreshold = 0 };
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
            DeleteBarcodeLinksByEntry("toughhooks", item.Id);
            DeleteQrMappingsForEntryBarcodeValues(item.ExtraFields);
            _ = _hub.ToughHooks.DeleteAsync(item.Id);
        }

        if (selected.Count > 0) Touch();
    }

    private void ToughHooks_SetSection(object sender, RoutedEventArgs e)
    {
        var selected = ToughHooksGrid.SelectedItems.Cast<ToughHookEntry>().ToList();
        if (selected.Count == 0) return;
        var current = selected[0].SectionLabel;
        var label = PromptForText("Set Section", "Section label for selected rows:", current);
        if (label is null) return;
        foreach (var item in selected) { item.SectionLabel = label; _ = _hub.ToughHooks.UpsertAsync(item); }
        Touch();
        _toughHooksView?.Refresh();
    }

    private void ToughHooks_ClearSection(object sender, RoutedEventArgs e)
    {
        var selected = ToughHooksGrid.SelectedItems.Cast<ToughHookEntry>().ToList();
        foreach (var item in selected) { item.SectionLabel = string.Empty; _ = _hub.ToughHooks.UpsertAsync(item); }
        if (selected.Count > 0) { Touch(); _toughHooksView?.Refresh(); }
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
            // Unmap this barcode value from every scan column and BarcodeLink
            UnmapQrValueFromAllEntries(item.QrValue);
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

    private void QrMappings_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (QrGenAutoFromSelection?.IsChecked != true || _qrGenSyncing)
            return;

        if (QrMappingsGrid.SelectedItem is not QrClassMapping selected)
            return;

        if (string.IsNullOrWhiteSpace(selected.QrValue))
            return;

        _qrGenSyncing = true;
        QrGenPayload.Text = selected.QrValue.Trim();
        _qrGenSyncing = false;
        UpdateQrGeneratorPreview();
    }

    private void QrGenPadUpcA_Click(object sender, RoutedEventArgs e)
    {
        string raw = System.Text.RegularExpressions.Regex.Replace(QrGenPayload.Text, @"\D", "");
        if (raw.Length < 11)
        {
            MessageBox.Show("Payload must contain at least 11 digits.", "Pad to UPC-A",
                            MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        int lead = QrGenUpcALeadDigit.SelectedIndex; // 0–9
        // If already 12+ digits treat digits 2–11 (indices 1–10) as the 10-digit core;
        // if exactly 11 digits treat all 11 as digits 2–12 (drop last, recalculate check).
        string core = raw.Length >= 12 ? raw.Substring(1, 10) : raw.Substring(0, 10);
        var digits = new int[12];
        digits[0] = lead;
        for (int i = 0; i < 10; i++)
            digits[i + 1] = core[i] - '0';
        int sum = 0;
        for (int i = 0; i < 11; i++)
            sum += digits[i] * (i % 2 == 0 ? 3 : 1);
        digits[11] = (10 - (sum % 10)) % 10;
        QrGenPayload.Text = string.Concat(digits);
        QrGenTypeUpcA.IsChecked = true;
    }

    private void QrGenerator_UseSelected(object sender, RoutedEventArgs e)
    {
        if (QrMappingsGrid.SelectedItem is not QrClassMapping selected || string.IsNullOrWhiteSpace(selected.QrValue))
        {
            StatusText = "Select a QR mapping row with a QR Value first.";
            return;
        }

        _qrGenSyncing = true;
        QrGenPayload.Text = selected.QrValue.Trim();
        _qrGenSyncing = false;
        UpdateQrGeneratorPreview();
        StatusText = "Loaded selected QR Value into generator.";
    }

    private void QrGenerator_CopyZpl(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_qrGenCurrentZpl))
        {
            StatusText = "Nothing to copy yet. Generate a label first.";
            return;
        }

        Clipboard.SetText(_qrGenCurrentZpl);
        StatusText = "Copied ZPL to clipboard.";
    }

    private void QrMappings_Save(object sender, RoutedEventArgs e)
    {
        // Commit any in-progress cell edit then force a save of all current rows
        QrMappingsGrid.CommitEdit(DataGridEditingUnit.Row, exitEditingMode: true);
        foreach (var item in _hub.QrMappings.GetAll())
            _ = _hub.QrMappings.UpsertAsync(item);
        Touch();
        StatusText = "QR Mappings saved.";
    }

    private void QrGen_ResetToDefault(object sender, RoutedEventArgs e)
    {
        _qrGenSyncing = true;
        try
        {
            InitializeQrGenerator();
        }
        finally
        {
            _qrGenSyncing = false;
        }
        StatusText = "QR Generator reset to defaults.";
    }

    private void QrGenerator_Print(object sender, RoutedEventArgs e)
    {
        if (QrGenPreview is null)
            return;

        BitmapSource? preview = QrGenPreview.Source as BitmapSource;
        if (preview is null)
        {
            UpdateQrGeneratorPreview();
            preview = QrGenPreview.Source as BitmapSource;
        }

        if (preview is null)
        {
            StatusText = "Nothing to print yet. Generate a label first.";
            return;
        }

        var labelWidthIn = ParseDoubleOrDefault(QrGenLabelWidthIn?.Text, 4.0, 0.5, 12.0);
        var labelHeightIn = ParseDoubleOrDefault(QrGenLabelHeightIn?.Text, 2.0, 0.5, 12.0);
        var description = $"CT Hub label {(QrGenTypeQr?.IsChecked == true ? "QR" : "Code128")}";

        ShowQrPrintPreview(preview, labelWidthIn, labelHeightIn, description);
    }

    private void ShowQrPrintPreview(BitmapSource preview, double labelWidthIn, double labelHeightIn, string description)
    {
        var document = BuildQrPrintDocument(preview, labelWidthIn, labelHeightIn);
        var viewer = new DocumentViewer
        {
            Document = document,
            Margin = new Thickness(0, 0, 0, 12),
            Background = new SolidColorBrush(Color.FromRgb(0x2A, 0x2A, 0x2A))
        };

        var printButton = new Button
        {
            Content = "Print...",
            Width = 92,
            Margin = new Thickness(0, 0, 8, 0),
            IsDefault = true
        };
        var closeButton = new Button
        {
            Content = "Close",
            Width = 92,
            IsCancel = true
        };

        var window = new Window
        {
            Title = "Print Preview",
            Owner = this,
            Width = 860,
            Height = 720,
            MinWidth = 640,
            MinHeight = 480,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = new SolidColorBrush(Color.FromRgb(0x1E, 0x1E, 0x1E)),
            Content = new DockPanel
            {
                LastChildFill = true,
                Margin = new Thickness(12)
            }
        };

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Children = { printButton, closeButton }
        };
        DockPanel.SetDock(buttons, Dock.Bottom);

        var root = (DockPanel)window.Content;
        root.Children.Add(buttons);
        root.Children.Add(viewer);

        closeButton.Click += (_, _) => window.Close();
        printButton.Click += (_, _) =>
        {
            var dialog = new PrintDialog();
            ConfigureQrPrintDialog(dialog, labelWidthIn, labelHeightIn);
            if (dialog.ShowDialog() != true)
                return;

            ConfigureQrPrintDialog(dialog, labelWidthIn, labelHeightIn);
            dialog.PrintDocument(document.DocumentPaginator, description);
            StatusText = $"Printed label to {dialog.PrintQueue?.FullName ?? "selected printer"}.";
            window.Close();
        };

        window.Loaded += (_, _) => viewer.FitToMaxPagesAcross(1);
        window.ShowDialog();
    }

    private static void ConfigureQrPrintDialog(PrintDialog dialog, double labelWidthIn, double labelHeightIn)
    {
        if (dialog.PrintTicket is null)
            return;

        dialog.PrintTicket.PageOrientation = labelWidthIn > labelHeightIn
            ? System.Printing.PageOrientation.Landscape
            : System.Printing.PageOrientation.Portrait;
        dialog.PrintTicket.PageMediaSize = new System.Printing.PageMediaSize(
            labelWidthIn * 96.0,
            labelHeightIn * 96.0);
    }

    private System.Windows.Documents.FixedDocument BuildQrPrintDocument(BitmapSource preview, double labelWidthIn, double labelHeightIn)
    {
        var pageWidth = Math.Max(1.0, labelWidthIn * 96.0);
        var pageHeight = Math.Max(1.0, labelHeightIn * 96.0);
        var fixedPage = new System.Windows.Documents.FixedPage
        {
            Width = pageWidth,
            Height = pageHeight,
            Background = Brushes.White
        };

        var image = new Image
        {
            Source = preview,
            Width = pageWidth,
            Height = pageHeight,
            Stretch = Stretch.Fill
        };
        System.Windows.Documents.FixedPage.SetLeft(image, 0);
        System.Windows.Documents.FixedPage.SetTop(image, 0);
        fixedPage.Children.Add(image);

        var pageContent = new System.Windows.Documents.PageContent();
        ((System.Windows.Markup.IAddChild)pageContent).AddChild(fixedPage);

        var document = new System.Windows.Documents.FixedDocument();
        document.DocumentPaginator.PageSize = new Size(pageWidth, pageHeight);
        document.Pages.Add(pageContent);
        return document;
    }

    private void QrGenerator_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_qrGenSyncing) return;
        UpdateQrGeneratorPreview();
    }

    private void QrGenerator_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_qrGenSyncing) return;
        UpdateQrGeneratorPreview();
    }

    private void QrGenerator_PresetChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_qrGenSyncing || QrGenPreset is null) return;

        var preset = QrGenPreset.SelectedIndex;
        _qrGenSyncing = true;
        try
        {
            switch (preset)
            {
                case 0: // 4x6 Shipping (203)
                    QrGenDpi.SelectedIndex = 0;
                    QrGenLabelWidthIn.Text = "4.0";
                    QrGenLabelHeightIn.Text = "6.0";
                    QrGenMarginX.Text = "24";
                    QrGenMarginY.Text = "24";
                    QrGenModuleDots.Text = "4";
                    QrGenQuietZone.Text = "4";
                    QrGenBarcodeHeight.Text = "220";
                    break;
                case 1: // 2x1 Asset Tag (300)
                    QrGenDpi.SelectedIndex = 1;
                    QrGenLabelWidthIn.Text = "2.0";
                    QrGenLabelHeightIn.Text = "1.0";
                    QrGenMarginX.Text = "16";
                    QrGenMarginY.Text = "12";
                    QrGenModuleDots.Text = "3";
                    QrGenQuietZone.Text = "2";
                    QrGenBarcodeHeight.Text = "90";
                    break;
                case 2: // 4x2 Product (203)
                    QrGenDpi.SelectedIndex = 0;
                    QrGenLabelWidthIn.Text = "4.0";
                    QrGenLabelHeightIn.Text = "2.0";
                    QrGenMarginX.Text = "24";
                    QrGenMarginY.Text = "24";
                    QrGenModuleDots.Text = "4";
                    QrGenQuietZone.Text = "4";
                    QrGenBarcodeHeight.Text = "120";
                    break;
                default:
                    break;
            }

            SyncQrGeneratorSlidersFromText();
        }
        finally
        {
            _qrGenSyncing = false;
        }

        UpdateQrGeneratorPreview();
    }

    private void QrGenerator_NumberSliderChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_qrGenSyncing) return;

        _qrGenSyncing = true;
        try
        {
            if (sender == QrGenLabelWidthInSlider)
                QrGenLabelWidthIn.Text = e.NewValue.ToString("0.0", CultureInfo.InvariantCulture);
            else if (sender == QrGenLabelHeightInSlider)
                QrGenLabelHeightIn.Text = e.NewValue.ToString("0.0", CultureInfo.InvariantCulture);
            else if (sender == QrGenMarginXSlider)
                QrGenMarginX.Text = ((int)Math.Round(e.NewValue)).ToString(CultureInfo.InvariantCulture);
            else if (sender == QrGenMarginYSlider)
                QrGenMarginY.Text = ((int)Math.Round(e.NewValue)).ToString(CultureInfo.InvariantCulture);
            else if (sender == QrGenModuleDotsSlider)
                QrGenModuleDots.Text = ((int)Math.Round(e.NewValue)).ToString(CultureInfo.InvariantCulture);
            else if (sender == QrGenQuietZoneSlider)
                QrGenQuietZone.Text = ((int)Math.Round(e.NewValue)).ToString(CultureInfo.InvariantCulture);
            else if (sender == QrGenBarcodeHeightSlider)
                QrGenBarcodeHeight.Text = ((int)Math.Round(e.NewValue)).ToString(CultureInfo.InvariantCulture);
        }
        finally
        {
            _qrGenSyncing = false;
        }

        UpdateQrGeneratorPreview();
    }

    private void QrGenerator_ToggleChanged(object sender, RoutedEventArgs e)
    {
        if (_qrGenSyncing) return;
        UpdateQrGeneratorPreview();
    }

    private void InitializeQrGenerator()
    {
        if (QrGenDpi is null) return;

        _qrGenSyncing = true;
        QrGenDpi.SelectedIndex = 0;
        QrGenPreset.SelectedIndex = 2;
        QrGenTypeQr.IsChecked = true;
        if (QrMappingsGrid.Items.Count > 0 && QrMappingsGrid.Items[0] is QrClassMapping first && !string.IsNullOrWhiteSpace(first.QrValue))
            QrGenPayload.Text = first.QrValue.Trim();
        SyncQrGeneratorSlidersFromText();
        _qrGenSyncing = false;

        UpdateQrGeneratorPreview();
    }

    private void SyncQrGeneratorSlidersFromText()
    {
        if (QrGenLabelWidthInSlider is null || QrGenLabelHeightInSlider is null ||
            QrGenMarginXSlider is null || QrGenMarginYSlider is null ||
            QrGenModuleDotsSlider is null || QrGenQuietZoneSlider is null ||
            QrGenBarcodeHeightSlider is null)
            return;

        QrGenLabelWidthInSlider.Value = ParseDoubleOrDefault(QrGenLabelWidthIn.Text, 4.0, 0.5, 12.0);
        QrGenLabelHeightInSlider.Value = ParseDoubleOrDefault(QrGenLabelHeightIn.Text, 2.0, 0.5, 12.0);
        QrGenMarginXSlider.Value = ParseIntOrDefault(QrGenMarginX.Text, 24, 0, 400);
        QrGenMarginYSlider.Value = ParseIntOrDefault(QrGenMarginY.Text, 24, 0, 400);
        QrGenModuleDotsSlider.Value = ParseIntOrDefault(QrGenModuleDots.Text, 4, 1, 40);
        QrGenQuietZoneSlider.Value = ParseIntOrDefault(QrGenQuietZone.Text, 4, 0, 20);
        QrGenBarcodeHeightSlider.Value = ParseIntOrDefault(QrGenBarcodeHeight.Text, 120, 20, 1200);
    }

    private void UpdateQrGeneratorPreview()
    {
        if (QrGenPreview is null || QrGenInfo is null || QrGenZplOutput is null)
            return;

        _qrGenSyncing = true;
        try
        {
            SyncQrGeneratorSlidersFromText();
        }
        finally
        {
            _qrGenSyncing = false;
        }

        var payload = (QrGenPayload.Text ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(payload)) payload = "SCAN_ME";

        var dpi = ParseIntOrDefault(QrGenDpi.Text, 203, 203, 600);
        var labelWidthIn = ParseDoubleOrDefault(QrGenLabelWidthIn.Text, 4.0, 0.5, 12.0);
        var labelHeightIn = ParseDoubleOrDefault(QrGenLabelHeightIn.Text, 2.0, 0.5, 12.0);
        var labelWidthDots = (int)Math.Round(labelWidthIn * dpi);
        var labelHeightDots = (int)Math.Round(labelHeightIn * dpi);

        var marginX = ParseIntOrDefault(QrGenMarginX.Text, 24, 0, 2000);
        var marginY = ParseIntOrDefault(QrGenMarginY.Text, 24, 0, 2000);
        var moduleDots = ParseIntOrDefault(QrGenModuleDots.Text, 4, 1, 40);
        var quietZone = ParseIntOrDefault(QrGenQuietZone.Text, 4, 0, 20);
        var barcodeHeight = ParseIntOrDefault(QrGenBarcodeHeight.Text, 120, 20, 1200);

        var isQr   = QrGenTypeQr.IsChecked   == true;
        var isUpcA = QrGenTypeUpcA.IsChecked  == true;
        var includeText = QrGenIncludeText.IsChecked == true;

        var canvas = new bool[Math.Max(1, labelWidthDots) * Math.Max(1, labelHeightDots)];
        var maxCodeWidth = Math.Max(32, labelWidthDots - (marginX * 2));
        var maxCodeHeight = Math.Max(32, labelHeightDots - (marginY * 2));

        var hints = new Dictionary<EncodeHintType, object>
        {
            [EncodeHintType.MARGIN] = Math.Max(0, quietZone)
        };

        var writer = new MultiFormatWriter();

        try
        {
            if (isQr)
            {
                var qrBase = writer.encode(payload, BarcodeFormat.QR_CODE, 1, 1, hints);
                var qrWidth = qrBase.Width * moduleDots;
                var qrHeight = qrBase.Height * moduleDots;

                if (qrWidth > maxCodeWidth || qrHeight > maxCodeHeight)
                {
                    var fitX = Math.Max(1, maxCodeWidth / Math.Max(1, qrBase.Width));
                    var fitY = Math.Max(1, maxCodeHeight / Math.Max(1, qrBase.Height));
                    moduleDots = Math.Max(1, Math.Min(fitX, fitY));
                    qrWidth = qrBase.Width * moduleDots;
                    qrHeight = qrBase.Height * moduleDots;
                }

                var offsetX = marginX + Math.Max(0, (maxCodeWidth - qrWidth) / 2);
                var offsetY = marginY + Math.Max(0, (maxCodeHeight - qrHeight) / 2);

                for (int y = 0; y < qrBase.Height; y++)
                {
                    for (int x = 0; x < qrBase.Width; x++)
                    {
                        if (!qrBase[x, y]) continue;
                        PaintRect(canvas, labelWidthDots, labelHeightDots,
                                  offsetX + (x * moduleDots),
                                  offsetY + (y * moduleDots),
                                  moduleDots,
                                  moduleDots);
                    }
                }

                var tl1 = QrGenTopLine1.Text ?? string.Empty;
                var tl2 = QrGenTopLine2.Text ?? string.Empty;
                var bl  = QrGenBottomLine.Text ?? string.Empty;
                _qrGenCurrentZpl = BuildQrZpl(labelWidthDots, labelHeightDots, marginX, marginY, moduleDots, payload, tl1, tl2, bl);
                QrGenInfo.Text = $"QR | {dpi} DPI | {labelWidthDots}x{labelHeightDots} dots | module {moduleDots} dots";
            }
            else
            {
                BarcodeFormat fmt = isUpcA ? BarcodeFormat.UPC_A : BarcodeFormat.CODE_128;
                var barMatrix = writer.encode(payload, fmt, maxCodeWidth, barcodeHeight, hints);
                var drawWidth = Math.Min(maxCodeWidth, barMatrix.Width);
                var drawHeight = Math.Min(maxCodeHeight, barMatrix.Height);
                var offsetX = marginX + Math.Max(0, (maxCodeWidth - drawWidth) / 2);
                var offsetY = marginY + Math.Max(0, (maxCodeHeight - drawHeight) / 2);

                for (int y = 0; y < drawHeight; y++)
                {
                    for (int x = 0; x < drawWidth; x++)
                    {
                        if (!barMatrix[x, y]) continue;
                        PaintRect(canvas, labelWidthDots, labelHeightDots,
                                  offsetX + x,
                                  offsetY + y,
                                  1,
                                  1);
                    }
                }

                var line1 = QrGenTopLine1.Text ?? string.Empty;
                var line2 = QrGenTopLine2.Text ?? string.Empty;
                var lineB = QrGenBottomLine.Text ?? string.Empty;
                if (isUpcA)
                {
                    _qrGenCurrentZpl = BuildUpcAZpl(labelWidthDots, labelHeightDots, marginX, marginY, moduleDots, barcodeHeight, includeText, payload, line1, line2, lineB);
                    QrGenInfo.Text = $"UPC-A | {dpi} DPI | {labelWidthDots}x{labelHeightDots} dots | height {barcodeHeight} dots";
                }
                else
                {
                    _qrGenCurrentZpl = BuildCode128Zpl(labelWidthDots, labelHeightDots, marginX, marginY, moduleDots, barcodeHeight, includeText, payload, line1, line2, lineB);
                    QrGenInfo.Text = $"Code128 | {dpi} DPI | {labelWidthDots}x{labelHeightDots} dots | height {barcodeHeight} dots";
                }
            }

            var bmp = BuildMonochromeBitmap(canvas, labelWidthDots, labelHeightDots);
            QrGenPreview.Source = bmp;
            QrGenZplOutput.Text = _qrGenCurrentZpl;
        }
        catch (Exception ex)
        {
            QrGenPreview.Source = null;
            QrGenInfo.Text = $"Generator error: {ex.Message}";
            QrGenZplOutput.Text = string.Empty;
            _qrGenCurrentZpl = string.Empty;
        }
    }

    private static int ParseIntOrDefault(string? raw, int fallback, int min, int max)
    {
        if (!int.TryParse(raw, out var parsed)) parsed = fallback;
        return Math.Clamp(parsed, min, max);
    }

    private static double ParseDoubleOrDefault(string? raw, double fallback, double min, double max)
    {
        if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed) &&
            !double.TryParse(raw, NumberStyles.Float, CultureInfo.CurrentCulture, out parsed))
            parsed = fallback;

        return Math.Clamp(parsed, min, max);
    }

    private static void PaintRect(bool[] canvas, int canvasWidth, int canvasHeight, int x, int y, int w, int h)
    {
        var x0 = Math.Clamp(x, 0, canvasWidth);
        var y0 = Math.Clamp(y, 0, canvasHeight);
        var x1 = Math.Clamp(x + w, 0, canvasWidth);
        var y1 = Math.Clamp(y + h, 0, canvasHeight);

        for (int py = y0; py < y1; py++)
        {
            var row = py * canvasWidth;
            for (int px = x0; px < x1; px++)
                canvas[row + px] = true;
        }
    }

    private static BitmapSource BuildMonochromeBitmap(bool[] canvas, int width, int height)
    {
        var stride = width * 4;
        var pixels = new byte[stride * height];

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                var i = (y * stride) + (x * 4);
                var on = canvas[(y * width) + x];
                byte v = on ? (byte)0 : (byte)255;
                pixels[i + 0] = v;
                pixels[i + 1] = v;
                pixels[i + 2] = v;
                pixels[i + 3] = 255;
            }
        }

        var bmp = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        bmp.Freeze();
        return bmp;
    }

    private static string BuildQrZpl(int labelWidthDots, int labelHeightDots, int marginX, int marginY, int moduleDots, string payload,
        string topLine1 = "", string topLine2 = "", string bottomLine = "")
    {
        var safe = payload.Replace("^", " ").Replace("~", " ");
        var lines = new List<string>
        {
            "^XA",
            "^MMT",
            $"^PW{labelWidthDots}",
            $"^LL{labelHeightDots}",
            "^LS0",
            $"^FO{marginX},{marginY}",
            $"^BQN,2,{Math.Max(1, moduleDots)}",
            $"^FDLA,{safe}^FS",
        };
        AppendTextLines(lines, marginX, marginY, 0, labelHeightDots, topLine1, topLine2, bottomLine);
        lines.Add("^PQ1,0,1,Y");
        lines.Add("^XZ");
        return string.Join("\n", lines);
    }

    private static string BuildUpcAZpl(int labelWidthDots, int labelHeightDots, int marginX, int marginY, int moduleDots, int heightDots, bool includeText, string payload,
        string topLine1 = "", string topLine2 = "", string bottomLine = "")
    {
        var safe = payload.Replace("^", " ").Replace("~", " ");
        var textFlag = includeText ? "Y" : "N";
        int h = Math.Max(20, heightDots);
        int barcodeBottomY = marginY + h;
        var lines = new List<string>
        {
            "^XA",
            "^MMT",
            $"^PW{labelWidthDots}",
            $"^LL{labelHeightDots}",
            "^LS0",
            $"^BY{Math.Max(1, moduleDots)},2,{h}",
            $"^FT{marginX},{barcodeBottomY}",
            $"^BUN,,{textFlag},N,N",
            $"^FD{safe}^FS",
        };
        AppendTextLines(lines, marginX, marginY, barcodeBottomY, labelHeightDots, topLine1, topLine2, bottomLine);
        lines.Add("^PQ1,0,1,Y");
        lines.Add("^XZ");
        return string.Join("\n", lines);
    }

    private static string BuildCode128Zpl(int labelWidthDots, int labelHeightDots, int marginX, int marginY, int moduleDots, int heightDots, bool includeText, string payload,
        string topLine1 = "", string topLine2 = "", string bottomLine = "")
    {
        var safe = payload.Replace("^", " ").Replace("~", " ");
        var textFlag = includeText ? "Y" : "N";
        int h = Math.Max(20, heightDots);
        int barcodeBottomY = marginY + h;
        var lines = new List<string>
        {
            "^XA",
            "^MMT",
            $"^PW{labelWidthDots}",
            $"^LL{labelHeightDots}",
            "^LS0",
            $"^BY{Math.Max(1, moduleDots)},2,{h}",
            $"^FT{marginX},{barcodeBottomY}",
            $"^BCN,{h},{textFlag},N,N",
            $"^FD{safe}^FS",
        };
        AppendTextLines(lines, marginX, marginY, barcodeBottomY, labelHeightDots, topLine1, topLine2, bottomLine);
        lines.Add("^PQ1,0,1,Y");
        lines.Add("^XZ");
        return string.Join("\n", lines);
    }

    private static void AppendTextLines(List<string> lines, int marginX, int marginY, int barcodeBottomY, int labelHeightDots,
        string topLine1, string topLine2, string bottomLine)
    {
        const int fontSize = 20;
        const int lineGap  = 24;
        int y = barcodeBottomY + lineGap;
        if (!string.IsNullOrWhiteSpace(topLine1))
        {
            var t = topLine1.Replace("^", " ").Replace("~", " ");
            lines.Add($"^FT{marginX},{y}^A0N,{fontSize},{fontSize}^FD{t}^FS");
            y += lineGap;
        }
        if (!string.IsNullOrWhiteSpace(topLine2))
        {
            var t = topLine2.Replace("^", " ").Replace("~", " ");
            lines.Add($"^FT{marginX},{y}^A0N,{fontSize},{fontSize}^FD{t}^FS");
        }
        if (!string.IsNullOrWhiteSpace(bottomLine))
        {
            var t = bottomLine.Replace("^", " ").Replace("~", " ");
            lines.Add($"^FT{marginX},{labelHeightDots - marginY}^A0N,{fontSize},{fontSize}^FD{t}^FS");
        }
    }

    // ── Shipping Supplys handlers ─────────────────────────────────────────────

    private void ShippingSupplys_Add(object sender, RoutedEventArgs e)
    {
        var entry = new ShippingSupplyEntry { Dimensions = "New box", Bundle = 0, Single = 0, StockThreshold = 0 };
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
            DeleteBarcodeLinksByEntry("shippingsupplys", item.Id);
            DeleteQrMappingsForEntryBarcodeValues(item.ExtraFields);
            _ = _hub.ShippingSupplys.DeleteAsync(item.Id);
        }

        if (selected.Count > 0) Touch();
    }

    private void ShippingSupplys_SetSection(object sender, RoutedEventArgs e)
    {
        var selected = ShippingSupplysGrid.SelectedItems.Cast<ShippingSupplyEntry>().ToList();
        if (selected.Count == 0) return;
        var current = selected[0].SectionLabel;
        var label = PromptForText("Set Section", "Section label for selected rows:", current);
        if (label is null) return;
        foreach (var item in selected) { item.SectionLabel = label; _ = _hub.ShippingSupplys.UpsertAsync(item); }
        Touch();
        _shippingSupplysView?.Refresh();
    }

    private void ShippingSupplys_ClearSection(object sender, RoutedEventArgs e)
    {
        var selected = ShippingSupplysGrid.SelectedItems.Cast<ShippingSupplyEntry>().ToList();
        foreach (var item in selected) { item.SectionLabel = string.Empty; _ = _hub.ShippingSupplys.UpsertAsync(item); }
        if (selected.Count > 0) { Touch(); _shippingSupplysView?.Refresh(); }
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
            AddDevCdpLog($"Launched debug {DevBrowserKind} on port {debugPort}. Refreshing tabs...");
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
    private bool _pdfEditorIsWebMode;
    private bool _pdfEditorIsRunEditMode;
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

        if (_pdfEditorIsWebMode)
            await NavigatePdfEditorWebViewAsync(row.Name);
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

                var sldSpacingX = GetSpacingXSlider();
                var sldSpacingY = GetSpacingYSlider();
                var txtSpacingX = GetSpacingXTextBox();
                var txtSpacingY = GetSpacingYTextBox();
                if (sldSpacingX is not null && txtSpacingX is not null
                    && global.TryGetProperty("textSpacingX", out var vs1) && vs1.TryGetDouble(out var ds1))
                {
                    txtSpacingX.Text   = ds1.ToString("0.#", CultureInfo.InvariantCulture);
                    sldSpacingX.Value  = Math.Clamp(ds1, sldSpacingX.Minimum, sldSpacingX.Maximum);
                }
                if (sldSpacingY is not null && txtSpacingY is not null
                    && global.TryGetProperty("textSpacingY", out var vs2) && vs2.TryGetDouble(out var ds2))
                    SetSliderAndText(sldSpacingY, txtSpacingY, ds2 * 100);
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
        var sldSpacingX  = GetSpacingXSlider();
        var sldSpacingY  = GetSpacingYSlider();
        var txtSpacingX  = GetSpacingXTextBox();
        var txtSpacingY  = GetSpacingYTextBox();
        SetSliderAndText(SldSizeY, TxtSizeY, 100);
        SetSliderAndText(SldSizeX, TxtSizeX, 100);
        SetSliderAndText(SldZoomX, TxtZoomX, 100);
        SetSliderAndText(SldZoomY, TxtZoomY, 100);
        if (sldPageSizeX is not null && txtPageSizeX is not null)
            SetSliderAndText(sldPageSizeX, txtPageSizeX, 100);
        if (sldPageSizeY is not null && txtPageSizeY is not null)
            SetSliderAndText(sldPageSizeY, txtPageSizeY, 100);
        if (sldSpacingX is not null && txtSpacingX is not null)
        {
            txtSpacingX.Text  = "0";
            sldSpacingX.Value = 0;
        }
        if (sldSpacingY is not null && txtSpacingY is not null)
            SetSliderAndText(sldSpacingY, txtSpacingY, 100);
        TxtFont.Text      = "Verdana";
        ChkBold.IsChecked = false;
        _pdfEditorSyncing = false;
        RefreshPdfEditorSurface();
    }

    private void PdfEditorResetDefaults_Click(object sender, RoutedEventArgs e)
    {
        ResetEditorToDefaults();
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
    private Slider? GetSpacingXSlider() => FindName("SldSpacingX") as Slider;
    private Slider? GetSpacingYSlider() => FindName("SldSpacingY") as Slider;
    private TextBox? GetSpacingXTextBox() => FindName("TxtSpacingX") as TextBox;
    private TextBox? GetSpacingYTextBox() => FindName("TxtSpacingY") as TextBox;

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
        var sldSpacingX  = GetSpacingXSlider();
        var sldSpacingY  = GetSpacingYSlider();
        var txtSpacingX  = GetSpacingXTextBox();
        var txtSpacingY  = GetSpacingYTextBox();
        if (_pdfEditorSyncing || SldSizeY is null || SldSizeX is null || SldZoomX is null || SldZoomY is null
            || sldPageSizeX is null || sldPageSizeY is null || txtPageSizeX is null || txtPageSizeY is null
            || sldSpacingX is null || sldSpacingY is null || txtSpacingX is null || txtSpacingY is null) return;
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
            else if (tb == txtSpacingX && double.TryParse(tb.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var v7))
                sldSpacingX.Value = Math.Clamp(v7, sldSpacingX.Minimum, sldSpacingX.Maximum);
            else if (tb == txtSpacingY && double.TryParse(tb.Text, out var v8))
                sldSpacingY.Value = Math.Clamp(v8, sldSpacingY.Minimum, sldSpacingY.Maximum);
        }
        finally
        {
            _pdfEditorSyncing = false;
        }

        if (tb == TxtZoomX || tb == TxtZoomY)
            _ = CaptureWebViewViewportReferenceAsync();

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

    private void SldSpacingX_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        var txtSpacingX = GetSpacingXTextBox();
        if (_pdfEditorSyncing || txtSpacingX is null) return;
        _pdfEditorSyncing = true;
        txtSpacingX.Text = e.NewValue.ToString("0.#", CultureInfo.InvariantCulture);
        _pdfEditorSyncing = false;
        RefreshPdfEditorSurface();
    }

    private void SldSpacingY_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        var txtSpacingY = GetSpacingYTextBox();
        if (_pdfEditorSyncing || txtSpacingY is null) return;
        _pdfEditorSyncing = true;
        txtSpacingY.Text = ((int)Math.Round(e.NewValue)).ToString();
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

    private async void PdfEditorRunEdit_Click(object sender, RoutedEventArgs e)
    {
        _pdfEditorIsRunEditMode = !_pdfEditorIsRunEditMode;
        UpdatePdfEditorModeUi();
        if (PdfEditorWebView.CoreWebView2 is not null)
            await PdfEditorWebView.CoreWebView2.ExecuteScriptAsync(
                $"window._readerSetRunEditMode && window._readerSetRunEditMode({(_pdfEditorIsRunEditMode ? "true" : "false")});");
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

    private System.Windows.Controls.Primitives.Popup? _webZoomPopup;
    private System.Windows.Controls.TextBlock? _webZoomLabel;
    private System.Windows.Threading.DispatcherTimer? _webZoomTimer;
    private System.Windows.Threading.DispatcherTimer? _pdfLayoutTimer;

    private void EnsureWebZoomPopup()
    {
        if (_webZoomPopup is not null) return;
        if (PdfEditorScroll is null || PdfEditorWebView is null)
            return;

        _webZoomLabel = new System.Windows.Controls.TextBlock
        {
            Foreground = System.Windows.Media.Brushes.White,
            FontFamily = new System.Windows.Media.FontFamily("Consolas"),
            FontSize = 16,
            FontWeight = FontWeights.Bold
        };
        var border = new System.Windows.Controls.Border
        {
            Background = new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromArgb(0xCC, 0x0D, 0x0D, 0x0D)),
            BorderBrush = new System.Windows.Media.SolidColorBrush(
                System.Windows.Media.Color.FromArgb(0x44, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(12, 6, 12, 6),
            Child = _webZoomLabel
        };
        _webZoomPopup = new System.Windows.Controls.Primitives.Popup
        {
            AllowsTransparency = true,
            Placement = System.Windows.Controls.Primitives.PlacementMode.RelativePoint,
            PlacementTarget = PdfEditorScroll,
            HorizontalOffset = 16,
            VerticalOffset = 16,
            IsHitTestVisible = false,
            Child = border
        };
        _webZoomPopup.Opened += (_, _) =>
        {
            if (System.Windows.PresentationSource.FromVisual(_webZoomPopup.Child)
                is System.Windows.Interop.HwndSource src)
                SetWindowPos(src.Handle, new IntPtr(-1), 0, 0, 0, 0, 0x0003);
        };
    }

    private void PositionWebZoomPopup()
    {
        if (_webZoomPopup is null)
            return;

        FrameworkElement target = _pdfEditorIsWebMode ? PdfEditorWebView : PdfEditorScroll;
        _webZoomPopup.PlacementTarget = target;
        var hostHeight = target.ActualHeight;
        _webZoomPopup.HorizontalOffset = 16;
        _webZoomPopup.VerticalOffset = Math.Max(16, hostHeight - 52);
    }

    private void ShowWebZoomPopup(string label)
    {
        EnsureWebZoomPopup();
        if (_webZoomPopup is null || _webZoomLabel is null)
            return;

        _webZoomLabel!.Text = label;
        PositionWebZoomPopup();
        _webZoomPopup!.IsOpen = true;
        _webZoomTimer?.Stop();
        _webZoomTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
        _webZoomTimer.Tick += (_, _) => { _webZoomPopup.IsOpen = false; _webZoomTimer?.Stop(); };
        _webZoomTimer.Start();
    }

    private void ShowWebZoomPopup(int pct)
    {
        ShowWebZoomPopup($"{pct}%");
    }

    private void ShowPdfLayoutIndicator(string label, FrameworkElement? anchor = null, bool autoHide = false)
    {
        if (PdfEditorResizeIndicatorBorder is null || PdfEditorResizeIndicatorText is null)
            return;

        PdfEditorResizeIndicatorText.Text = label;
        PdfEditorResizeIndicatorBorder.Visibility = Visibility.Visible;
        PositionPdfLayoutIndicator(anchor);
        _pdfLayoutTimer?.Stop();

        if (!autoHide)
            return;

        _pdfLayoutTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1200) };
        _pdfLayoutTimer.Tick += (_, _) =>
        {
            if (PdfEditorResizeIndicatorBorder is not null)
                PdfEditorResizeIndicatorBorder.Visibility = Visibility.Collapsed;
            _pdfLayoutTimer?.Stop();
        };
        _pdfLayoutTimer.Start();
    }

    private void PositionPdfLayoutIndicator(FrameworkElement? anchor)
    {
        if (anchor is null || PdfEditorResizeIndicatorBorder is null)
            return;

        if (PdfEditorResizeIndicatorBorder.Parent is not Canvas indicatorLayer)
            return;

        PdfEditorResizeIndicatorBorder.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var desired = PdfEditorResizeIndicatorBorder.DesiredSize;
        var center = anchor.TranslatePoint(
            new Point(anchor.ActualWidth / 2, anchor.ActualHeight / 2),
            indicatorLayer);

        var left = center.X - (desired.Width / 2);
        var top = center.Y - (desired.Height / 2);
        var maxLeft = Math.Max(0, indicatorLayer.ActualWidth - desired.Width);
        var maxTop = Math.Max(0, indicatorLayer.ActualHeight - desired.Height);

        Canvas.SetLeft(PdfEditorResizeIndicatorBorder, Math.Clamp(left, 0, maxLeft));
        Canvas.SetTop(PdfEditorResizeIndicatorBorder, Math.Clamp(top, 0, maxTop));
    }

    private static string FormatSplitLabel(double firstRatio)
    {
        var firstPct = (int)Math.Round(firstRatio * 100);
        firstPct = Math.Clamp(firstPct, 0, 100);
        return $"{firstPct}% / {100 - firstPct}%";
    }

    private double GetPdfEditorFileListRatio()
    {
        var total = PdfEditorFileListRow.ActualHeight + PdfEditorWorkspaceRow.ActualHeight;
        if (total <= 0)
            return 0.5;
        return Math.Clamp(PdfEditorFileListRow.ActualHeight / total, 0.1, 0.9);
    }

    private double GetPdfEditorPanelRatio()
    {
        var total = PdfEditorSettingsColumn.ActualWidth + PdfEditorPreviewColumn.ActualWidth;
        if (total <= 0)
            return 0.5;
        return Math.Clamp(PdfEditorSettingsColumn.ActualWidth / total, 0.1, 0.9);
    }

    private void ApplySavedPdfEditorLayout()
    {
        if (PdfEditorTabGrid is null || PdfEditorSurfaceGrid is null)
            return;

        _applyingPdfEditorLayout = true;
        try
        {
            var fileListRatio = _settings.PdfEditorFileListRatio;
            if (fileListRatio > 0 && fileListRatio < 1)
            {
                PdfEditorFileListRow.Height = new GridLength(fileListRatio, GridUnitType.Star);
                PdfEditorWorkspaceRow.Height = new GridLength(1 - fileListRatio, GridUnitType.Star);
            }

            var panelRatio = _settings.PdfEditorPanelRatio;
            if (panelRatio > 0 && panelRatio < 1)
            {
                PdfEditorSettingsColumn.Width = new GridLength(panelRatio, GridUnitType.Star);
                PdfEditorPreviewColumn.Width = new GridLength(1 - panelRatio, GridUnitType.Star);
            }
        }
        finally
        {
            _applyingPdfEditorLayout = false;
        }
    }

    private void SavePdfEditorLayout()
    {
        if (_applyingPdfEditorLayout)
            return;

        _settings.PdfEditorFileListRatio = GetPdfEditorFileListRatio();
        _settings.PdfEditorPanelRatio = GetPdfEditorPanelRatio();
        _settings.Save();
    }

    private void PdfEditorRowSplitter_DragStarted(object sender, DragStartedEventArgs e)
    {
        ShowPdfLayoutIndicator(FormatSplitLabel(GetPdfEditorFileListRatio()), sender as FrameworkElement);
    }

    private void PdfEditorRowSplitter_DragDelta(object sender, DragDeltaEventArgs e)
    {
        ShowPdfLayoutIndicator(FormatSplitLabel(GetPdfEditorFileListRatio()), sender as FrameworkElement);
    }

    private void PdfEditorRowSplitter_DragCompleted(object sender, DragCompletedEventArgs e)
    {
        var ratio = GetPdfEditorFileListRatio();
        PdfEditorFileListRow.Height = new GridLength(ratio, GridUnitType.Star);
        PdfEditorWorkspaceRow.Height = new GridLength(1 - ratio, GridUnitType.Star);
        SavePdfEditorLayout();
        ShowPdfLayoutIndicator(FormatSplitLabel(ratio), sender as FrameworkElement, autoHide: true);
    }

    private void PdfEditorColumnSplitter_DragStarted(object sender, DragStartedEventArgs e)
    {
        ShowPdfLayoutIndicator(FormatSplitLabel(GetPdfEditorPanelRatio()), sender as FrameworkElement);
    }

    private void PdfEditorColumnSplitter_DragDelta(object sender, DragDeltaEventArgs e)
    {
        ShowPdfLayoutIndicator(FormatSplitLabel(GetPdfEditorPanelRatio()), sender as FrameworkElement);
    }

    private void PdfEditorColumnSplitter_DragCompleted(object sender, DragCompletedEventArgs e)
    {
        var ratio = GetPdfEditorPanelRatio();
        PdfEditorSettingsColumn.Width = new GridLength(ratio, GridUnitType.Star);
        PdfEditorPreviewColumn.Width = new GridLength(1 - ratio, GridUnitType.Star);
        SavePdfEditorLayout();
        ShowPdfLayoutIndicator(FormatSplitLabel(ratio), sender as FrameworkElement, autoHide: true);
    }

    private Task PushWebZoomFactorToReader()
    {
        if (!_pdfEditorIsWebMode || PdfEditorWebView?.CoreWebView2 is null)
            return Task.CompletedTask;

        var zoom = _pdfEditorWebZoomFactor.ToString("0.####", CultureInfo.InvariantCulture);
        return PdfEditorWebView.ExecuteScriptAsync(
            $"window._readerSetHostZoomFactor && window._readerSetHostZoomFactor({zoom});");
    }

    private async Task CaptureWebViewViewportReferenceAsync()
    {
        if (!_pdfEditorIsWebMode || PdfEditorWebView?.CoreWebView2 is null)
            return;

        try
        {
            await PdfEditorWebView.ExecuteScriptAsync(
                "window._readerCaptureViewportReference && window._readerCaptureViewportReference();");
        }
        catch
        {
            // Ignore navigation timing issues; the reader will establish a baseline on render.
        }
    }

    private async Task NavigatePdfEditorWebViewAsync(string filename)
    {
        if (!_pdfEditorIsWebMode || string.IsNullOrWhiteSpace(filename))
            return;

        await PdfEditorWebView.EnsureCoreWebView2Async();
        PdfEditorWebView.ZoomFactor = _pdfEditorWebZoomFactor;
        PdfEditorWebView.CoreWebView2.WebMessageReceived -= OnWebZoomMessage;
        PdfEditorWebView.CoreWebView2.WebMessageReceived += OnWebZoomMessage;
        PdfEditorWebView.ZoomFactorChanged -= OnWebViewZoomFactorChanged;
        PdfEditorWebView.ZoomFactorChanged += OnWebViewZoomFactorChanged;
        PdfEditorWebView.CoreWebView2.NavigationCompleted -= OnPdfEditorWebViewNavigated;
        PdfEditorWebView.CoreWebView2.NavigationCompleted += OnPdfEditorWebViewNavigated;
        PdfEditorWebView.Source = new Uri(
            $"http://localhost:{HubServer.Port}/reader.html?file={Uri.EscapeDataString(filename)}");
    }

    private async void PdfEditorWebMode_Click(object sender, RoutedEventArgs e)
    {
        _pdfEditorIsWebMode = !_pdfEditorIsWebMode;
        PdfEditorScroll.Visibility = _pdfEditorIsWebMode ? Visibility.Collapsed : Visibility.Visible;
        PdfEditorWebView.Visibility = _pdfEditorIsWebMode ? Visibility.Visible : Visibility.Collapsed;
        if (!_pdfEditorIsWebMode) { if (_webZoomPopup is not null) _webZoomPopup.IsOpen = false; }

        if (_pdfEditorIsWebMode && !string.IsNullOrEmpty(_pdfEditorCurrentFile))
            await NavigatePdfEditorWebViewAsync(_pdfEditorCurrentFile);

        UpdatePdfEditorModeUi();
    }

    private void OnWebViewZoomFactorChanged(object? sender, object e)
    {
        _pdfEditorWebZoomFactor = PdfEditorWebView.ZoomFactor;
        _ = PushWebZoomFactorToReader();
        var pct = (int)Math.Round(_pdfEditorWebZoomFactor * 100);
        Dispatcher.Invoke(() => ShowWebZoomPopup(pct));
    }

    private void OnWebZoomMessage(object? sender, Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            var outer = System.Text.Json.JsonDocument.Parse(e.WebMessageAsJson).RootElement;
            var inner = outer.ValueKind == System.Text.Json.JsonValueKind.String
                ? outer.GetString()!
                : e.WebMessageAsJson;
            using var doc = System.Text.Json.JsonDocument.Parse(inner);
            var root = doc.RootElement;
            if (root.TryGetProperty("type", out var t) && t.GetString() == "ctrlscroll"
                && root.TryGetProperty("delta", out var d))
            {
                const double step = 0.1;
                var dir = d.GetInt32();
                Dispatcher.Invoke(() =>
                {
                    var next = Math.Round(PdfEditorWebView.ZoomFactor + dir * step, 2);
                    next = Math.Clamp(next, PdfEditorWebZoomMin, PdfEditorWebZoomMax);
                    _pdfEditorWebZoomFactor = next;
                    PdfEditorWebView.ZoomFactor = next;
                    _ = PushWebZoomFactorToReader();
                    ShowWebZoomPopup((int)Math.Round(_pdfEditorWebZoomFactor * 100));
                });
            }
        }
        catch { }
    }

    private async void OnPdfEditorWebViewNavigated(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        PdfEditorWebView.CoreWebView2.NavigationCompleted -= OnPdfEditorWebViewNavigated;
        if (e.IsSuccess)
            await PushSettingsToWebView();
    }

    private async Task PushSettingsToWebView()
    {
        if (!_pdfEditorIsWebMode || PdfEditorWebView?.CoreWebView2 is null)
            return;

        var txtSpacingX = GetSpacingXTextBox();
        var txtSpacingY = GetSpacingYTextBox();

        double sizeY    = ParsePercentOrDefault(TxtSizeY?.Text, 100) / 100.0;
        double sizeX    = ParsePercentOrDefault(TxtSizeX?.Text, 100) / 100.0;
        double zoomX    = ParsePercentOrDefault(TxtZoomX?.Text, 100) / 100.0;
        double zoomY    = ParsePercentOrDefault(TxtZoomY?.Text, 100) / 100.0;
        double spacingX = ParseDoubleOrDefault(txtSpacingX?.Text, 0, -2, 12);
        double spacingY = ParsePercentOrDefault(txtSpacingY?.Text, 100) / 100.0;
        bool   bold     = ChkBold?.IsChecked == true;
        string font     = TxtFont?.Text?.Trim() ?? string.Empty;

        var bundle = new
        {
            readerTextSizeY    = sizeY.ToString("0.####", CultureInfo.InvariantCulture),
            readerTextSizeX    = sizeX.ToString("0.####", CultureInfo.InvariantCulture),
            readerPageZoomX    = zoomX.ToString("0.####", CultureInfo.InvariantCulture),
            readerPageZoomY    = zoomY.ToString("0.####", CultureInfo.InvariantCulture),
            readerTextSpacingX = spacingX.ToString("0.####", CultureInfo.InvariantCulture),
            readerTextSpacingY = spacingY.ToString("0.####", CultureInfo.InvariantCulture),
            readerForceBold    = bold ? "1" : "0",
            readerFont         = font
        };

        var json = JsonSerializer.Serialize(bundle);
        var jsJson = json.Replace("\\", "\\\\").Replace("'", "\\'");
        await PdfEditorWebView.ExecuteScriptAsync(
            $"window._readerSetHostZoomFactor && window._readerSetHostZoomFactor({_pdfEditorWebZoomFactor.ToString("0.####", CultureInfo.InvariantCulture)});window._readerApplySettings && window._readerApplySettings(JSON.parse('{jsJson}'))");
    }

    private async void PdfEditorSave_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_pdfEditorCurrentFile)) return;

        try
        {
            var response = await SavePdfGlobalOverridesAsync(_pdfEditorCurrentFile);
            StatusText = response.IsSuccessStatusCode
                ? $"Saved global settings: {_pdfEditorCurrentFile}"
                : $"Save failed: {(int)response.StatusCode}";
        }
        catch (Exception ex)
        {
            StatusText = $"Save failed: {ex.Message}";
        }
    }

    private async void PdfEditorSaveAll_Click(object sender, RoutedEventArgs e)
    {
        if (PdfFileRows.Count == 0)
        {
            StatusText = "Save all skipped: no PDF files are loaded.";
            return;
        }

        var savedCount = 0;
        var failed = new List<string>();

        foreach (var row in PdfFileRows)
        {
            if (string.IsNullOrWhiteSpace(row?.Name))
                continue;

            try
            {
                var response = await SavePdfGlobalOverridesAsync(row.Name);
                if (response.IsSuccessStatusCode)
                {
                    savedCount++;
                }
                else
                {
                    failed.Add($"{row.Name} ({(int)response.StatusCode})");
                }
            }
            catch (Exception ex)
            {
                failed.Add($"{row.Name} ({ex.Message})");
            }
        }

        if (failed.Count == 0)
        {
            StatusText = $"Saved global settings for {savedCount} PDF file(s).";
            return;
        }

        var failedPreview = string.Join(", ", failed.Take(3));
        if (failed.Count > 3)
            failedPreview += ", ...";

        StatusText = $"Save all finished: {savedCount} saved, {failed.Count} failed. {failedPreview}";
    }

    private async Task<HttpResponseMessage> SavePdfGlobalOverridesAsync(string filename)
    {
        var json = await BuildGlobalOverridesJsonAsync(filename);
        return await SavePdfOverridesAsync(filename, json);
    }

    private async Task<HttpResponseMessage> SavePdfOverridesAsync(string filename, string json)
    {
        using var http = new System.Net.Http.HttpClient();
        var url = $"http://localhost:{HubServer.Port}/api/pdf-overrides/{Uri.EscapeDataString(filename)}";
        using var content = new System.Net.Http.StringContent(json, System.Text.Encoding.UTF8, "application/json");
        return await http.PostAsync(url, content);
    }

    private async Task<string> BuildGlobalOverridesJsonAsync(string filename)
    {
        JsonNode? preservedRuns = null;

        try
        {
            using var http = new System.Net.Http.HttpClient();
            var url = $"http://localhost:{HubServer.Port}/api/pdf-overrides/{Uri.EscapeDataString(filename)}";
            var response = await http.GetAsync(url);
            if (response.IsSuccessStatusCode)
            {
                var existingJson = await response.Content.ReadAsStringAsync();
                if (!string.IsNullOrWhiteSpace(existingJson))
                {
                    var existingRoot = JsonNode.Parse(existingJson) as JsonObject;
                    preservedRuns = existingRoot?["runs"]?.DeepClone();
                }
            }
        }
        catch
        {
            preservedRuns = null;
        }

        var payload = BuildGlobalOverridesPayload(preservedRuns);
        return payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    private JsonObject BuildGlobalOverridesPayload(JsonNode? preservedRuns = null)
    {
        var txtPageSizeX = GetPageSizeXTextBox();
        var txtPageSizeY = GetPageSizeYTextBox();
        var txtSpacingX  = GetSpacingXTextBox();
        var txtSpacingY  = GetSpacingYTextBox();
        double sizeY     = double.TryParse(TxtSizeY.Text, out var v1)  ? v1 / 100.0 : 1.0;
        double sizeX     = double.TryParse(TxtSizeX.Text, out var v2)  ? v2 / 100.0 : 1.0;
        double zoomX     = double.TryParse(TxtZoomX.Text, out var v3)  ? v3 / 100.0 : 1.0;
        double zoomY     = double.TryParse(TxtZoomY.Text, out var v4)  ? v4 / 100.0 : 1.0;
        double pageSizeX = double.TryParse(txtPageSizeX?.Text, out var v5) ? v5 / 100.0 : 1.0;
        double pageSizeY = double.TryParse(txtPageSizeY?.Text, out var v6) ? v6 / 100.0 : 1.0;
        double spacingX  = double.TryParse(txtSpacingX?.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out var v7) ? v7 : 0.0;
        double spacingY  = double.TryParse(txtSpacingY?.Text, out var v8)  ? v8 / 100.0 : 1.0;

        var payload = new JsonObject
        {
            ["global"] = new JsonObject
            {
                ["textSizeY"] = sizeY,
                ["textSizeX"] = sizeX,
                ["pageZoomX"] = zoomX,
                ["pageZoomY"] = zoomY,
                ["pageSizeX"] = pageSizeX,
                ["pageSizeY"] = pageSizeY,
                ["textSpacingX"] = spacingX,
                ["textSpacingY"] = spacingY,
                ["forceBold"] = ChkBold.IsChecked == true,
                ["fontOverride"] = TxtFont.Text.Trim()
            }
        };

        if (preservedRuns is not null)
            payload["runs"] = preservedRuns;

        return payload;
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

        if (_pdfEditorIsWebMode)
        {
            _ = PushSettingsToWebView();
            return;
        }

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
            double sizeY = Math.Clamp(ParsePercentOrDefault(TxtSizeY?.Text, 100), 10, 1000) / 100.0;
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
        double sizeY = Math.Clamp(ParsePercentOrDefault(TxtSizeY?.Text, 100), 10, 1000) / 100.0;
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
        var editButton    = FindName("PdfEditorEditModeBtn") as Button;
        var viewButton    = FindName("PdfEditorViewModeBtn") as Button;
        var webButton     = FindName("PdfEditorWebModeBtn")  as Button;
        var runEditButton = FindName("PdfEditorRunEditBtn")  as Button;

        if (editButton is null || viewButton is null)
            return;

        ApplyPdfEditorModeButtonState(editButton, _pdfEditorIsEditMode);
        ApplyPdfEditorModeButtonState(viewButton, !_pdfEditorIsEditMode);
        if (webButton is not null)
            ApplyPdfEditorModeButtonState(webButton, _pdfEditorIsWebMode);
        if (runEditButton is not null)
        {
            runEditButton.Content = (_pdfEditorIsRunEditMode ? "✏ Edit Runs: On" : "✏ Edit Runs: Off");
            ApplyPdfEditorModeButtonState(runEditButton, _pdfEditorIsRunEditMode);
        }
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
