using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using QuickTransfer.Infrastructure;
using QuickTransfer.Models;
using QuickTransfer.Services;

namespace QuickTransfer.ViewModels;

public sealed partial class MainViewModel : ObservableObject
{
    private readonly TransferCore core;
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
    private string text = "", status = "", activeSendId = "", sentText = "";
    private string[] sentFiles = Array.Empty<string>();
    private bool ready, sending;

    public Peer? SelectedDevice { get => selectedDevice; set { if (Set(ref selectedDevice, value)) SendCommand.Refresh(); } }
    public string Text { get => text; set { if (Set(ref text, value)) SendCommand.Refresh(); } }
    public string Status { get => status; set { if (Set(ref status, value)) Notify(nameof(HasStatus)); } }
    public bool HasStatus => Status.Length > 0;
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
        SendCommand = new Command(_ => Send(), _ => ready && !sending && SelectedDevice != null && (Text.Length > 0 || Attachments.Count > 0));
        RemoveCommand = new Command(value => { if (value is Attachment file) Attachments.Remove(file); });
        RefreshCommand = new Command(_ => Run(() => { if (ready) core.Send(new { action = "refresh" }); else Restart(); }));
        Attachments.CollectionChanged += (_, _) => { Notify(nameof(HasAttachments)); SendCommand.Refresh(); };
        Devices.CollectionChanged += (_, _) => Notify(nameof(NoDevices));
        Records.CollectionChanged += (_, _) => Notify(nameof(NoRecords));
        ActiveTransfers.CollectionChanged += (_, _) => Notify(nameof(HasActiveTransfers));
        core.Events += HandleBatch;
        core.Error += error => { ready = false; UpdateCommands(); Report(error); };
    }

    public void Report(Exception error) => Status = "操作失败：" + error.Message;
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

    public async Task LoadReceivedAsync()
    {
        try
        {
            foreach (var file in await FileService.ReadReceivedAsync(Settings.Root))
            {
                if (Records.Any(record => record.Files.Any(item => string.Equals(item.Path, file.Path, StringComparison.OrdinalIgnoreCase)))) continue;
                if (Records.Count >= 30) break;
                var directory = Path.GetDirectoryName(file.Path)!;
                var record = new TransferRecord(file.Path, file.Name, 0)
                {
                    State = "已接收", Active = false, BatchId = Path.GetFileName(directory),
                    StartedAt = new DateTimeOffset(Directory.GetCreationTimeUtc(directory))
                };
                record.Files.Add(file);
                record.FilesChanged();
                Records.Add(record);
                PublishFiles(record, false);
            }
        }
        catch (Exception error) { Report(error); }
    }

    private void Send()
    {
        if (!SendCommand.CanExecute(null)) return;
        activeSendId = "win-" + Guid.NewGuid().ToString("N");
        sentText = Text;
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

    public void Probe(string host, int port) => Run(() => core.Send(new { action = "probe", host, port }));
    public void Answer(string id, bool accept, bool remember) => Run(() => core.Send(new { action = accept ? "accept" : "decline", id, remember }));
    public void Restart()
    {
        ready = false;
        Devices.Clear();
        SelectedDevice = null;
        UpdateCommands();
        Run(() => core.Restart(Settings));
    }
}
