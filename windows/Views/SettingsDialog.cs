using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Microsoft.Win32;
using QuickTransfer.Models;
using QuickTransfer.Services;

namespace QuickTransfer.Views;

public sealed class SettingsDialog : Window
{
    private readonly MainWindow main;
    private readonly TextBox aliasField;
    private readonly TextBox directoryField;
    private readonly ComboBox heicSelect;
    private readonly CheckBox groupCheck;
    private readonly Slider retentionSlider;
    private readonly TextBlock retentionValue;
    private readonly (int Days, Button Button)[] presetButtons;
    private readonly TextBlock cacheSummary;
    private readonly Button clearCacheButton;
    private readonly TextBlock errorText;

    public string DeviceAlias => aliasField.Text;
    public string ReceiveDirectory => directoryField.Text;
    public HeicReceiveFormat HeicReceiveFormat => (HeicReceiveFormat)heicSelect.SelectedIndex;
    public bool GroupGalleryByTime => groupCheck.IsChecked == true;
    public int CacheRetentionDays => Math.Clamp((int)Math.Round(retentionSlider.Value), 1, 365);

    public SettingsDialog(MainWindow owner)
    {
        main = owner;
        Owner = owner;
        Title = "设置";
        Width = 440;
        MaxHeight = 720;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        FontFamily = owner.FontFamily;
        FontSize = owner.FontSize;
        SetResourceReference(BackgroundProperty, "PageBrush");
        SetResourceReference(ForegroundProperty, "TextBrush");

        var settings = owner.Model.Settings;
        var outer = new DockPanel { Margin = new Thickness(18, 16, 18, 18) };

        // Footer
        var footer = new DockPanel { Margin = new Thickness(0, 16, 0, 0) };
        var quit = new Button { Content = "退出快传", Height = 34 };
        quit.Click += (_, _) =>
        {
            DialogResult = false;
            Close();
            ((App)Application.Current).Quit();
        };
        DockPanel.SetDock(quit, Dock.Left);

        var rightButtons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "取消", IsCancel = true, Height = 34, Margin = new Thickness(0, 0, 8, 0) };
        var save = new Button { Content = "保存", IsDefault = true, Height = 34, Style = (Style)FindResource("PrimaryButton") };
        save.Click += OnSaveClick;
        rightButtons.Children.Add(cancel);
        rightButtons.Children.Add(save);
        DockPanel.SetDock(rightButtons, Dock.Right);
        footer.Children.Add(quit);
        footer.Children.Add(rightButtons);
        DockPanel.SetDock(footer, Dock.Bottom);
        outer.Children.Add(footer);

        // Body
        var body = new StackPanel();

        // Card 1: 设备与接收
        var generalContent = new StackPanel();
        generalContent.Children.Add(SectionLabel("设备名称", topMargin: 0));
        aliasField = new TextBox { Text = settings.Alias, Height = 34 };
        System.Windows.Automation.AutomationProperties.SetName(aliasField, "设备名称");
        generalContent.Children.Add(aliasField);

        generalContent.Children.Add(SectionLabel("保存目录"));
        var folderRow = new DockPanel();
        var browse = new Button { Content = "选择…", Height = 34, Margin = new Thickness(8, 0, 0, 0) };
        System.Windows.Automation.AutomationProperties.SetName(browse, "选择保存目录");
        directoryField = new TextBox { Text = settings.ReceiveDirectory, Height = 34 };
        System.Windows.Automation.AutomationProperties.SetName(directoryField, "保存目录");
        browse.Click += (_, _) =>
        {
            var picker = new OpenFolderDialog
            {
                Title = "选择保存目录",
                InitialDirectory = Directory.Exists(directoryField.Text) ? directoryField.Text : Path.GetDirectoryName(settings.ReceiveDirectory)
            };
            if (picker.ShowDialog(this) == true)
            {
                directoryField.Text = picker.FolderName;
                directoryField.CaretIndex = directoryField.Text.Length;
            }
        };
        DockPanel.SetDock(browse, Dock.Right);
        folderRow.Children.Add(browse);
        folderRow.Children.Add(directoryField);
        generalContent.Children.Add(folderRow);

        generalContent.Children.Add(SectionLabel("接收 HEIC"));
        heicSelect = new ComboBox
        {
            ItemsSource = new[] { "保留原格式", "转为 JPG", "转为 PNG" },
            SelectedIndex = (int)settings.HeicReceiveFormat,
            Height = 34,
            Style = (Style)FindResource("Select")
        };
        System.Windows.Automation.AutomationProperties.SetName(heicSelect, "接收 HEIC");
        generalContent.Children.Add(heicSelect);

        groupCheck = new CheckBox
        {
            Content = "按时间分组显示文件",
            IsChecked = settings.GroupGalleryByTime,
            Margin = new Thickness(0, 14, 0, 2)
        };
        generalContent.Children.Add(groupCheck);
        body.Children.Add(CreateCard(generalContent));

        // Card 2: 手动添加设备
        var peerRow = new DockPanel();
        var addPeerButton = new Button { Content = "添加设备…", Height = 32, VerticalAlignment = VerticalAlignment.Center };
        addPeerButton.Click += (_, _) => main.OpenAddPeerDialog(this);
        DockPanel.SetDock(addPeerButton, Dock.Right);
        var peerInfo = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
        peerInfo.Children.Add(new TextBlock { Text = "手动添加设备", FontWeight = FontWeights.SemiBold });
        var peerHint = new TextBlock { Text = "通过 IP 地址直连局域网设备", FontSize = 12, Margin = new Thickness(0, 2, 0, 0) };
        peerHint.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush");
        peerInfo.Children.Add(peerHint);
        peerRow.Children.Add(addPeerButton);
        peerRow.Children.Add(peerInfo);
        body.Children.Add(CreateCard(peerRow, topMargin: 12));

        // Card 3: 发送缓存
        var cacheContent = new StackPanel();
        var retentionHeader = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
        retentionValue = new TextBlock { FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        retentionValue.SetResourceReference(TextBlock.ForegroundProperty, "AccentBrush");
        DockPanel.SetDock(retentionValue, Dock.Right);
        var retentionTitle = new TextBlock { Text = "发送缓存保留时间", FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        retentionHeader.Children.Add(retentionValue);
        retentionHeader.Children.Add(retentionTitle);
        cacheContent.Children.Add(retentionHeader);

        retentionSlider = new Slider
        {
            Minimum = 1,
            Maximum = 365,
            Value = settings.CacheRetentionDays,
            IsSnapToTickEnabled = true,
            TickFrequency = 1,
            TickPlacement = TickPlacement.None,
            Margin = new Thickness(0, 2, 0, 10)
        };
        System.Windows.Automation.AutomationProperties.SetName(retentionSlider, "发送缓存保留天数");
        cacheContent.Children.Add(retentionSlider);

        var presetsGrid = new UniformGrid { Columns = 4, Margin = new Thickness(0, 0, 0, 12) };
        var presetDays = new[] { 3, 7, 30, 365 };
        presetButtons = new (int, Button)[presetDays.Length];
        for (var i = 0; i < presetDays.Length; i++)
        {
            var days = presetDays[i];
            var chip = new Button
            {
                Content = days + "天",
                Style = (Style)FindResource("PresetChipButton"),
                Margin = new Thickness(i == 0 ? 0 : 4, 0, i == presetDays.Length - 1 ? 0 : 4, 0)
            };
            chip.Click += (_, _) => retentionSlider.Value = days;
            presetButtons[i] = (days, chip);
            presetsGrid.Children.Add(chip);
        }
        cacheContent.Children.Add(presetsGrid);

        var divider = new Border { Height = 1, Margin = new Thickness(0, 0, 0, 10) };
        divider.SetResourceReference(Border.BackgroundProperty, "BorderBrush");
        cacheContent.Children.Add(divider);

        var cacheFooter = new DockPanel();
        clearCacheButton = new Button
        {
            Content = "立即清理",
            Height = 30,
            Style = (Style)FindResource("DangerButton"),
            IsEnabled = false
        };
        clearCacheButton.Click += OnClearCacheClick;
        DockPanel.SetDock(clearCacheButton, Dock.Right);
        cacheSummary = new TextBlock { Text = "正在计算缓存…", FontSize = 12, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) };
        cacheSummary.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush");
        cacheFooter.Children.Add(clearCacheButton);
        cacheFooter.Children.Add(cacheSummary);
        cacheContent.Children.Add(cacheFooter);

        body.Children.Add(CreateCard(cacheContent, topMargin: 12));

        errorText = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(2, 10, 2, 0),
            Visibility = Visibility.Collapsed
        };
        errorText.SetResourceReference(TextBlock.ForegroundProperty, "DangerBrush");
        body.Children.Add(errorText);

        var scroll = new ScrollViewer
        {
            Content = body,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        outer.Children.Add(scroll);
        Content = outer;

        retentionSlider.ValueChanged += (_, _) => UpdateRetentionUi();
        UpdateRetentionUi();
        Loaded += async (_, _) =>
        {
            aliasField.Focus();
            aliasField.SelectAll();
            await RefreshCacheSummaryAsync();
        };
        ThemeManager.Attach(this);
    }

    private Border CreateCard(UIElement child, double topMargin = 0)
    {
        var border = new Border
        {
            Style = (Style)FindResource("Card"),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(14, 12, 14, 12),
            Margin = new Thickness(0, topMargin, 0, 0),
            Child = child
        };
        return border;
    }

    private static TextBlock SectionLabel(string text, double topMargin = 12) =>
        new() { Text = text, Margin = new Thickness(0, topMargin, 0, 6) };

    private void UpdateRetentionUi()
    {
        var days = CacheRetentionDays;
        retentionValue.Text = $"{days} 天";
        foreach (var (preset, button) in presetButtons)
        {
            if (preset == days)
            {
                button.SetResourceReference(BackgroundProperty, "SelectBrush");
                button.SetResourceReference(BorderBrushProperty, "AccentBrush");
                button.SetResourceReference(ForegroundProperty, "AccentBrush");
            }
            else
            {
                button.SetResourceReference(BackgroundProperty, "PageBrush");
                button.SetResourceReference(BorderBrushProperty, "ControlBorderBrush");
                button.SetResourceReference(ForegroundProperty, "TextBrush");
            }
        }
    }

    private async Task RefreshCacheSummaryAsync()
    {
        var root = main.Model.Settings.Root;
        var stats = await Task.Run(() => OutboxCache.Measure(root));
        if (stats.Count == 0)
        {
            cacheSummary.Text = "当前无发送缓存";
            clearCacheButton.IsEnabled = false;
        }
        else
        {
            cacheSummary.Text = $"当前缓存：{stats.Count} 项 · {Attachment.FormatSize(stats.TotalBytes)}";
            clearCacheButton.IsEnabled = true;
        }
    }

    private async void OnClearCacheClick(object sender, RoutedEventArgs args)
    {
        var confirm = new PromptWindow(this, "清理发送缓存", "立即清理", "取消");
        confirm.AddPreview("清理后会移除发送临时缓存及对应的临时记录，不会影响已保存的接收文件或原文件。");
        if (confirm.ShowDialog() != true) return;
        clearCacheButton.IsEnabled = false;
        await main.Model.ClearOutboxCacheNowAsync();
        await RefreshCacheSummaryAsync();
    }

    private void OnSaveClick(object sender, RoutedEventArgs args)
    {
        if (string.IsNullOrWhiteSpace(aliasField.Text))
        {
            errorText.Text = "设备名称不能为空";
            errorText.Visibility = Visibility.Visible;
            return;
        }
        try
        {
            ReceiveDirectories.EnsureWritable(directoryField.Text);
        }
        catch (Exception error)
        {
            errorText.Text = "保存目录不可用：" + error.Message;
            errorText.Visibility = Visibility.Visible;
            return;
        }
        DialogResult = true;
    }
}
