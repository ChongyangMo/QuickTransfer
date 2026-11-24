using System;
using System.ComponentModel;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Microsoft.Win32;
using QuickTransfer.Controls;
using QuickTransfer.Models;
using QuickTransfer.Services;
using QuickTransfer.ViewModels;
using QuickTransfer.Views;

namespace QuickTransfer;

public partial class MainWindow : Window
{
    public MainViewModel Model { get; }
    private readonly BonjourPublisher bonjour = new();
    private PromptWindow? incomingDialog;
    private string incomingId = "";
    private readonly HashSet<string> pendingRequests = new();
    private readonly GalleryDragSelection galleryDragSelection;

    public MainWindow(MainViewModel model)
    {
        Model = model;
        InitializeComponent();
        DataContext = model;
        galleryDragSelection = new GalleryDragSelection(GalleryList, GallerySurface, item =>
        {
            Model.IsSelecting = true;
            if (item != null) selectionAnchor = item;
        });
        ThemeManager.Attach(this);
        model.Ready += async port =>
        {
            try { await bonjour.PublishAsync(port); }
            catch (Exception error) { Model.Status = "设备广播失败：" + error.Message; }
        };
        model.Incoming += value =>
        {
            var id = MainViewModel.String(value, "id");
            pendingRequests.Add(id);
            Dispatcher.BeginInvoke(() => { if (pendingRequests.Remove(id)) Receive(value); }, DispatcherPriority.Normal);
        };
        model.DismissIncoming += id =>
        {
            pendingRequests.Remove(id);
            if (incomingId == id) { incomingId = ""; incomingDialog?.Close(); }
        };
        model.TextReceived += (alias, text) => Dispatcher.BeginInvoke(() => ShowReceivedText(alias, text));
        Activated += (_, _) => _ = Model.PruneMissingGalleryFilesAsync();
    }

    protected override void OnClosing(CancelEventArgs args)
    {
        if (!((App)Application.Current).Exiting)
        {
            args.Cancel = true;
            textEditor?.Hide();
            Hide();
        }
        base.OnClosing(args);
    }

    private async void PickFiles(object sender, RoutedEventArgs args)
    {
        try
        {
            var picker = new OpenFileDialog { Multiselect = true, CheckFileExists = true, Title = "选择文件" };
            if (picker.ShowDialog(this) == true) await Model.AddFilesAsync(picker.FileNames);
        }
        catch (Exception error) { Model.Report(error); }
    }

    private void AddPeer(object sender, RoutedEventArgs args) => OpenAddPeerDialog(this);

    internal void OpenAddPeerDialog(Window? owner = null)
    {
        var dialog = new PromptWindow(owner ?? this, "手动添加设备", "连接");
        var host = dialog.AddField("IP 地址", "");
        host.Tag = "例如 192.168.1.10";
        dialog.Validate = () => TryParseHostAndPort(host.Text, out _, out _) ? "" : "请输入有效的 IP 地址";
        if (dialog.ShowDialog() == true && TryParseHostAndPort(host.Text, out var parsedHost, out var parsedPort))
            Model.Probe(parsedHost, parsedPort);
    }

    private static bool TryParseHostAndPort(string input, out string host, out int port)
    {
        host = "";
        port = 53317;
        var trimmed = input.Trim();
        if (string.IsNullOrWhiteSpace(trimmed)) return false;
        var colon = trimmed.LastIndexOf(':');
        if (colon > 0 && trimmed.IndexOf(':') == colon)
        {
            var hostPart = trimmed[..colon].Trim();
            var portPart = trimmed[(colon + 1)..].Trim();
            if (string.IsNullOrWhiteSpace(hostPart) || !ValidPort(portPart)) return false;
            host = hostPart;
            port = int.Parse(portPart);
            return true;
        }
        host = trimmed;
        return true;
    }

    private static bool ValidPort(string value) => int.TryParse(value, out var port) && port is >= 1 and <= 65535;

    private void DismissToast(object sender, MouseButtonEventArgs args)
    {
        args.Handled = true;
        Model.DismissToast();
    }

    private void Receive(JsonElement value)
    {
        var id = MainViewModel.String(value, "id");
        if (Model.VerifyReceive(value)) { Model.Answer(id, true, false); return; }
        if (incomingDialog != null || OwnedWindows.OfType<PromptWindow>().Any(dialog => dialog.IsVisible))
        { Model.Answer(id, false, false); return; }
        Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
        var dialog = new PromptWindow(this, MainViewModel.String(value, "alias"), "接收", "拒绝");
        var preview = MainViewModel.String(value, "text");
        if (preview.Length == 0) preview = value.GetProperty("count").GetInt32() + " 个文件";
        dialog.AddPreview(preview);
        var remember = dialog.AddCheckBox("记住此设备，自动接收");
        incomingId = id;
        incomingDialog = dialog;
        try
        {
            var accepted = dialog.ShowDialog() == true;
            if (incomingId == id) Model.Answer(id, accepted, accepted && remember.IsChecked == true);
        }
        finally { incomingDialog = null; incomingId = ""; }
    }

    private void OnKeyDown(object sender, KeyEventArgs args)
    {
        if (HandleGalleryKey(args)) { args.Handled = true; return; }
        if (args.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.Control)
        { Model.SendCommand.Execute(null); args.Handled = true; }
        else if (args.Key == Key.V && Keyboard.Modifiers == ModifierKeys.Control && Keyboard.FocusedElement is not TextBox)
        { _ = PasteAsync(); args.Handled = true; }
        else if (args.Key == Key.O && Keyboard.Modifiers == ModifierKeys.Control)
        { PickFiles(sender, args); args.Handled = true; }
        else if (args.Key == Key.R && Keyboard.Modifiers == ModifierKeys.Control)
        { Model.RefreshCommand.Execute(null); args.Handled = true; }
        else if (args.Key == Key.T && Keyboard.Modifiers == ModifierKeys.Control)
        { ShowTextEditor(); args.Handled = true; }
        else if (args.Key == Key.OemComma && Keyboard.Modifiers == ModifierKeys.Control)
        { OpenSettings(sender, args); args.Handled = true; }
    }

    private void Exit(object sender, RoutedEventArgs args) => ((App)Application.Current).Quit();
}
