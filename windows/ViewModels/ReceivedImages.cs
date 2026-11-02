using System;
using System.Diagnostics;
using System.Threading.Tasks;
using QuickTransfer.Models;
using QuickTransfer.Services;

namespace QuickTransfer.ViewModels;

public sealed partial class MainViewModel
{
    private async Task CompleteReceiveAsync(TransferRecord record, string path, HeicReceiveFormat format)
    {
        if (format != HeicReceiveFormat.Original && HeicConversion.IsHeic(path))
        {
            record.State = "正在转换";
            try { path = await HeicConversion.ConvertReceivedAsync(Settings.Root, path, format); }
            catch (Exception error)
            {
                Status = "HEIC 转换失败，已保留原文件：" + error.Message;
                Trace.WriteLine(Status);
            }
        }
        record.Active = false;
        ActiveTransfers.Remove(record);
        record.State = "已接收";
        await LoadRecordFilesAsync(record, new[] { path });
    }
}
