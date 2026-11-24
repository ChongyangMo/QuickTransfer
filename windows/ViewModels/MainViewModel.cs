using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using QuickTransfer.Infrastructure;
using QuickTransfer.Models;
using QuickTransfer.Services;

namespace QuickTransfer.ViewModels;

public sealed partial class MainViewModel : ObservableObject
{
    private readonly TransferCore core;
    private readonly ReceivedFileStore receivedFiles;
    private readonly HashSet<string> pinnedPaths;
    private readonly HashSet<string> lastLivePeerIds = new(StringComparer.Ordinal);
    private CancellationTokenSource? toastCts;
    private CancellationTokenSource? graceCleanupCts;
    private DateTimeOffset reconnectGraceUntil = DateTimeOffset.MinValue;
    private bool suppressPeerSave;
    public SettingsStore Settings { get; }
    public FileService FileService { get; } = new();
    public ObservableCollection<Peer> Devices { get; } = new();
    public ObservableCollection<Attachment> Attachments { get; } = new();
    public ObservableCollection<TransferRecord> Records { get; } = new();
    public ObservableCollection<TransferRecord> ActiveTransfers { get; } = new();
    public ObservableCollection<GalleryItem> Gallery { get; } = new();
    public event Action<JsonElement>? Incoming;
    public event Action<string, string>? TextReceived;
    public event Action<string>? DismissIncoming;
    public event Action<int>? Ready;
    private Peer? selectedDevice;
    private string text = "", status = "", activeSendId = "", sentText = "", sentPeerAlias = "";
    private string toastText = "";
    private bool toastSuccess = true;
    private string[] sentFiles = Array.Empty<string>();
    private bool ready, sending;

    public Peer? SelectedDevice
    {
        get => selectedDevice;
        set
        {
            if (!Set(ref selectedDevice, value)) return;
            SendCommand.Refresh();
            if (value != null && !suppressPeerSave)
            {
                var peerId = value.Id;
                _ = Task.Run(() => { try { Settings.SaveLastPeer(peerId); } catch { } });
            }
        }
    }
    public string Text { get => text; set { if (Set(ref text, value)) SendCommand.Refresh(); } }
    public string Status { get => status; set { if (Set(ref status, value)) Notify(nameof(HasStatus)); } }
    public bool HasStatus => Status.Length > 0;
    public string ToastText { get => toastText; private set { if (Set(ref toastText, value)) Notify(nameof(HasToast)); } }
    public bool ToastSuccess { get => toastSuccess; private set => Set(ref toastSuccess, value); }
    public bool HasToast => ToastText.Length > 0;
    public bool HasAttachments => Attachments.Count > 0;
    public bool NoDevices => Devices.Count == 0;
    public bool NoRecords => Records.Count == 0;
    public bool HasActiveTransfers => ActiveTransfers.Count > 0;
    public string SendLabel => sending ? "发送中" : "发送";
    public bool IsTransferring => sending || Records.Any(record => record.Active);
    public Command SendCommand { get; }
    public Command RemoveCommand { get; }
    public Command RefreshCommand { get; }

    public MainViewModel(TransferCore core, SettingsStore settings)
    {
        this.core = core;
        Settings = settings;
        pinnedPaths = settings.ReadPinnedPaths();
        receivedFiles = new ReceivedFileStore(settings.Root);
        SendCommand = new Command(_ => Send(), _ => ready && !sending && SelectedDevice != null && (Text.Length > 0 || Attachments.Count > 0));
        RemoveCommand = new Command(value => { if (value is Attachment file) Attachments.Remove(file); });
        RefreshCommand = new Command(_ => Run(() =>
        {
            if (ready)
            {
                core.Send(new { action = "refresh" });
                ShowToast("正在刷新设备");
            }
            else Restart();
        }));
        Attachments.CollectionChanged += (_, _) => { Notify(nameof(HasAttachments)); SendCommand.Refresh(); };
        Devices.CollectionChanged += (_, _) => Notify(nameof(NoDevices));
        Records.CollectionChanged += (_, _) => Notify(nameof(NoRecords));
        ActiveTransfers.CollectionChanged += (_, _) => Notify(nameof(HasActiveTransfers));
        core.Events += HandleBatch;
        core.Error += error => { ready = false; UpdateCommands(); Report(error); };
        RestoreCachedPeers();
    }

    private void RestoreCachedPeers()
    {
        var cached = Settings.ReadRecentPeers();
        if (cached.Length == 0) return;
        suppressPeerSave = true;
        try
        {
            foreach (var item in cached)
            {
                if (string.IsNullOrWhiteSpace(item.Id)) continue;
                Devices.Add(new Peer(item.Id) { Alias = item.Alias, Mobile = item.Mobile });
            }
            SelectPreferredDevice();
        }
        finally { suppressPeerSave = false; }
        BeginReconnectGrace();
    }

    private void BeginReconnectGrace()
    {
        reconnectGraceUntil = DateTimeOffset.UtcNow.AddSeconds(3);
        graceCleanupCts?.Cancel();
        graceCleanupCts?.Dispose();
        var cts = new CancellationTokenSource();
        graceCleanupCts = cts;
        _ = CompleteReconnectGraceAsync(cts.Token);
    }

    private async Task CompleteReconnectGraceAsync(CancellationToken token)
    {
        try
        {
            await Task.Delay(3100, token);
            if (token.IsCancellationRequested) return;
            PruneStalePeers();
        }
        catch (OperationCanceledException) { }
    }

    private void PruneStalePeers()
    {
        var removedAny = false;
        foreach (var peer in Devices.Where(peer => !lastLivePeerIds.Contains(peer.Id)).ToArray())
        {
            Devices.Remove(peer);
            removedAny = true;
        }
        if (SelectedDevice != null && !Devices.Contains(SelectedDevice))
        {
            suppressPeerSave = true;
            try { SelectedDevice = null; }
            finally { suppressPeerSave = false; }
        }
        if (removedAny || SelectedDevice == null) SelectPreferredDevice();
        SendCommand.Refresh();
    }

    private void SelectPreferredDevice()
    {
        if (SelectedDevice != null && Devices.Contains(SelectedDevice)) return;
        suppressPeerSave = true;
        try
        {
            var lastId = Settings.LastPeerId;
            if (lastId.Length > 0)
            {
                var preferred = Devices.FirstOrDefault(peer => peer.Id == lastId);
                if (preferred != null) { SelectedDevice = preferred; return; }
            }
            if (Devices.Count == 1) SelectedDevice = Devices[0];
        }
        finally { suppressPeerSave = false; }
    }

    public void ShowToast(string message, bool success = true)
    {
        if (string.IsNullOrWhiteSpace(message)) return;
        toastCts?.Cancel();
        toastCts?.Dispose();
        var cts = new CancellationTokenSource();
        toastCts = cts;
        ToastSuccess = success;
        ToastText = message;
        _ = AutoDismissToastAsync(cts.Token, success ? 2200 : 3200);
    }

    public void DismissToast()
    {
        toastCts?.Cancel();
        toastCts?.Dispose();
        toastCts = null;
        ToastText = "";
    }

    private async Task AutoDismissToastAsync(CancellationToken token, int delayMs)
    {
        try
        {
            await Task.Delay(delayMs, token);
            if (!token.IsCancellationRequested) ToastText = "";
        }
        catch (OperationCanceledException) { }
    }

    public void Report(Exception error)
    {
        Status = "操作失败：" + error.Message;
        ShowToast(error.Message, false);
    }
    public void Run(Action action) { try { action(); } catch (Exception error) { Report(error); } }
    private void UpdateCommands() { SendCommand.Refresh(); RefreshCommand.Refresh(); Notify(nameof(SendLabel)); }

    public async Task AddFilesAsync(string[] paths)
    {
        var additions = await FileService.ReadFilesAsync(paths);
        var unique = additions.Where(file => !Attachments.Any(current => string.Equals(current.Path, file.Path, StringComparison.OrdinalIgnoreCase))).ToArray();
        if (Attachments.Count + unique.Length > 999) throw new InvalidOperationException("一次最多添加 999 个文件");
        foreach (var file in unique.Reverse())
        {
            Attachments.Insert(0, file);
        }
        Status = "";
    }

    private void Send()
    {
        if (!SendCommand.CanExecute(null)) return;
        activeSendId = "win-" + Guid.NewGuid().ToString("N");
        sentText = Text;
        sentPeerAlias = SelectedDevice!.Alias;
        sentFiles = Attachments.Select(file => file.Path).ToArray();
        sending = true;
        UpdateCommands();
        try
        {
            core.Send(new { action = "send", id = activeSendId, peer = SelectedDevice!.Id, text = Text.Length > 0 ? Text : null, paths = sentFiles });
            Status = "";
        }
        catch (Exception error) { sending = false; UpdateCommands(); Report(error); }
    }

    public void Probe(string host, int port) => Run(() =>
    {
        core.Send(new { action = "probe", host, port });
        ShowToast($"正在连接 {host}");
    });
    public void Answer(string id, bool accept, bool remember) => Run(() => core.Send(new { action = accept ? "accept" : "decline", id, remember }));
    public void Restart()
    {
        ready = false;
        lastLivePeerIds.Clear();
        BeginReconnectGrace();
        UpdateCommands();
        Run(() => core.Restart(Settings));
    }

    public bool IsPinnedPath(string path) => pinnedPaths.Contains(Path.GetFullPath(path));

    public void TogglePin(IEnumerable<Attachment> files)
    {
        var targets = files.Where(file => file != null).DistinctBy(file => file.Path, StringComparer.OrdinalIgnoreCase).ToArray();
        if (targets.Length == 0) return;
        var shouldPin = targets.Any(file => !file.IsPinned);
        foreach (var file in targets)
        {
            var full = Path.GetFullPath(file.Path);
            if (shouldPin) pinnedPaths.Add(full);
            else pinnedPaths.Remove(full);
        }
        foreach (var item in Gallery)
            item.File.IsPinned = pinnedPaths.Contains(Path.GetFullPath(item.File.Path));
        var snapshot = pinnedPaths.ToArray();
        _ = Task.Run(() => { try { Settings.SavePinnedPaths(snapshot); } catch { } });
        RebuildGalleryTimeline();
        ShowToast(shouldPin ? "已置顶" : "已取消置顶");
    }

    public async Task ResendFilesAsync(IEnumerable<Attachment> files)
    {
        var existing = files.Select(file => file.Path)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Where(File.Exists)
            .ToArray();
        if (existing.Length == 0)
        {
            ShowToast("原文件已移动或删除", false);
            return;
        }
        try
        {
            await AddFilesAsync(existing);
            ShowToast(existing.Length == 1 ? "已添加到待发送" : $"已添加 {existing.Length} 项到待发送");
        }
        catch (Exception error) { Report(error); }
    }

    public async Task RemoveGalleryItemsAsync(IEnumerable<Attachment> files)
    {
        var targets = new HashSet<string>(
            files.Select(file => Path.GetFullPath(file.Path)),
            StringComparer.OrdinalIgnoreCase);
        if (targets.Count == 0) return;
        var pinChanged = false;
        foreach (var item in Gallery.Where(item => targets.Contains(Path.GetFullPath(item.File.Path))).ToArray())
        {
            Gallery.Remove(item);
            if (pinnedPaths.Remove(Path.GetFullPath(item.File.Path))) pinChanged = true;
        }
        foreach (var record in Records.Where(r => !r.Active && !Gallery.Any(item => item.Record == r)).ToArray())
        {
            Records.Remove(record);
            rows.Remove(record.Id);
        }
        if (pinChanged)
        {
            var snapshot = pinnedPaths.ToArray();
            _ = Task.Run(() => { try { Settings.SavePinnedPaths(snapshot); } catch { } });
        }
        RebuildGalleryTimeline();
        try { await receivedFiles.RemoveAsync(targets); }
        catch { }
        ShowToast(targets.Count == 1 ? "已移除记录" : $"已移除 {targets.Count} 条记录");
    }

    private HashSet<string> BuildProtectedOutboxPaths(bool includePinned)
    {
        var protectedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in Attachments) protectedPaths.Add(Path.GetFullPath(item.Path));
        foreach (var record in Records.Where(r => r.Active))
            foreach (var file in record.Files)
                protectedPaths.Add(Path.GetFullPath(file.Path));
        if (includePinned)
            foreach (var path in pinnedPaths) protectedPaths.Add(path);
        return protectedPaths;
    }

    public async Task<int> CleanExpiredOutboxAsync()
    {
        var protectedPaths = BuildProtectedOutboxPaths(includePinned: true);
        var root = Settings.Root;
        var days = Settings.CacheRetentionDays;
        var (removedCount, removedPaths) = await Task.Run(() => OutboxCache.CleanExpired(root, days, protectedPaths));
        if (removedPaths.Count > 0) PruneRemovedOutboxItems(removedPaths);
        return removedCount;
    }

    public async Task<int> ClearOutboxCacheNowAsync()
    {
        var protectedPaths = BuildProtectedOutboxPaths(includePinned: false);
        var root = Settings.Root;
        var (removedCount, removedPaths) = await Task.Run(() => OutboxCache.ClearAll(root, protectedPaths));
        if (removedPaths.Count > 0) PruneRemovedOutboxItems(removedPaths);
        ShowToast(removedCount > 0 ? $"已清理 {removedCount} 项发送缓存" : "当前没有可清理的缓存");
        return removedCount;
    }

    private void PruneRemovedOutboxItems(HashSet<string> removedPaths)
    {
        var changed = false;
        var pinChanged = false;
        foreach (var item in Gallery.Where(item => removedPaths.Contains(Path.GetFullPath(item.File.Path))).ToArray())
        {
            Gallery.Remove(item);
            changed = true;
            if (pinnedPaths.Remove(Path.GetFullPath(item.File.Path))) pinChanged = true;
        }
        if (changed)
        {
            foreach (var record in Records.Where(r => !r.Active && !Gallery.Any(item => item.Record == r)).ToArray())
            {
                Records.Remove(record);
                rows.Remove(record.Id);
            }
            if (pinChanged)
            {
                var snapshot = pinnedPaths.ToArray();
                _ = Task.Run(() => { try { Settings.SavePinnedPaths(snapshot); } catch { } });
            }
            RebuildGalleryTimeline();
        }
    }
}
