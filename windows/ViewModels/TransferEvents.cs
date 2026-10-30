using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using QuickTransfer.Models;

namespace QuickTransfer.ViewModels;

public sealed partial class MainViewModel
{
    private readonly Dictionary<string, TransferRecord> rows = new();

    private void HandleBatch(IReadOnlyList<JsonElement> events)
    {
        foreach (var value in events)
        {
            try { Handle(value); }
            catch (Exception error) { Report(error); }
        }
    }

    private void Handle(JsonElement value)
    {
        var type = String(value, "type");
        var id = String(value, "id");
        rows.TryGetValue(id, out var record);
        switch (type)
        {
            case "ready":
                ready = true;
                Status = "";
                UpdateCommands();
                Ready?.Invoke((int)Number(value, "port"));
                break;
            case "devices":
                ReconcileDevices(value.GetProperty("devices"));
                break;
            case "offline":
                var offline = Devices.FirstOrDefault(peer => peer.Id == id);
                if (offline != null) Devices.Remove(offline);
                if (SelectedDevice?.Id == id) SelectedDevice = null;
                break;
            case "incoming": Incoming?.Invoke(value); break;
            case "dismiss": DismissIncoming?.Invoke(id); break;
            case "transfer":
                var batchId = String(value, "session", id);
                var row = new TransferRecord(id, String(value, "name"), Number(value, "size"))
                {
                    State = String(value, "direction") == "send" ? "正在发送" : "正在接收",
                    BatchId = batchId,
                    StartedAt = Records.FirstOrDefault(item => item.BatchId == batchId)?.StartedAt ?? DateTimeOffset.Now
                };
                AddRecord(row);
                if (value.TryGetProperty("paths", out var paths) && paths.ValueKind == JsonValueKind.Array)
                    _ = LoadRecordFilesAsync(row, paths.EnumerateArray().Select(path => path.GetString()!).ToArray());
                break;
            case "progress":
                if (record is { Active: true }) record.Progress = record.Size > 0 ? Math.Clamp(Number(value, "bytes") / record.Size * 100, 0, 100) : 0;
                break;
            case "sent":
            case "received":
                if (id == activeSendId)
                {
                    sending = false;
                    if (Text == sentText && Attachments.Select(file => file.Path).SequenceEqual(sentFiles))
                    { Text = ""; Attachments.Clear(); }
                    UpdateCommands();
                }
                if (record != null)
                {
                    record.Progress = 100;
                    record.Active = false;
                    ActiveTransfers.Remove(record);
                    record.State = type == "sent" ? "已发送" : "已接收";
                    if (type == "received") _ = LoadRecordFilesAsync(record, new[] { String(value, "path") });
                    else PublishFiles(record);
                }
                break;
            case "text":
                TextReceived?.Invoke(String(value, "alias"), String(value, "text"));
                break;
            case "failed":
            case "error":
            case "cancelled":
                if (id == activeSendId || (type == "error" && id.Length == 0 && sending && !rows.ContainsKey(activeSendId)))
                { sending = false; UpdateCommands(); }
                Status = String(value, "message", "传输已取消");
                if (record != null) { record.Active = false; ActiveTransfers.Remove(record); record.State = type == "cancelled" ? "已取消" : "传输失败"; }
                break;
        }
        VerifyEvent(value);
    }

    private void ReconcileDevices(JsonElement peers)
    {
        var ids = new HashSet<string>();
        foreach (var value in peers.EnumerateArray())
        {
            var id = String(value, "id");
            ids.Add(id);
            var peer = Devices.FirstOrDefault(item => item.Id == id);
            if (peer == null) { peer = new Peer(id); Devices.Add(peer); }
            peer.Alias = String(value, "alias");
            peer.Mobile = value.TryGetProperty("mobile", out var mobile) && mobile.ValueKind == JsonValueKind.True;
        }
        foreach (var peer in Devices.Where(peer => !ids.Contains(peer.Id)).ToArray()) Devices.Remove(peer);
        if (SelectedDevice != null && !Devices.Contains(SelectedDevice)) SelectedDevice = null;
        if (SelectedDevice == null && Devices.Count == 1) SelectedDevice = Devices[0];
        SendCommand.Refresh();
    }

    private void AddRecord(TransferRecord record)
    {
        if (rows.TryGetValue(record.Id, out var previous)) Records.Remove(previous);
        rows[record.Id] = record;
        Records.Insert(0, record);
        if (record.Active) ActiveTransfers.Add(record);
        while (Records.Count > 30)
        {
            var last = Records.LastOrDefault(item => !item.Active);
            if (last == null) break;
            Records.Remove(last);
            rows.Remove(last.Id);
            foreach (var item in Gallery.Where(item => item.Record == last).ToArray()) Gallery.Remove(item);
        }
        RebuildGalleryTimeline();
    }

    private async Task LoadRecordFilesAsync(TransferRecord record, string[] paths)
    {
        try
        {
            foreach (var file in await FileService.ReadFilesAsync(paths))
            {
                record.Files.Add(file);
            }
            record.FilesChanged();
            if (!record.Active && (record.State is "已发送" or "已接收") && Records.Contains(record)) PublishFiles(record);
        }
        catch (Exception error) { Report(error); }
    }

    private void PublishFiles(TransferRecord record, bool newest = true)
    {
        var additions = record.Files.Where(file => !Gallery.Any(item => item.Record == record && item.File.Path == file.Path)).ToArray();
        foreach (var file in newest ? additions.Reverse() : additions)
        {
            var item = new GalleryItem(record, file);
            if (newest) Gallery.Insert(0, item);
            else Gallery.Add(item);
        }
        RebuildGalleryTimeline();
    }

    internal static string String(JsonElement value, string name, string fallback = "") =>
        value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String ? property.GetString()! : fallback;
    private static double Number(JsonElement value, string name) =>
        value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.Number && property.TryGetDouble(out var number) ? number : 0;
}
