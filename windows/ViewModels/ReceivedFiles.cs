using System;
using System.Linq;
using System.Threading.Tasks;
using QuickTransfer.Models;

namespace QuickTransfer.ViewModels;

public sealed partial class MainViewModel
{
    public async Task LoadReceivedAsync()
    {
        try
        {
            foreach (var entry in await receivedFiles.ReadAsync())
            {
                if (Records.Any(record => record.Files.Any(item => string.Equals(item.Path, entry.Path, StringComparison.OrdinalIgnoreCase)))) continue;
                if (Records.Count >= 30) break;
                var file = (await FileService.ReadFilesAsync(new[] { entry.Path }))[0];
                var record = new TransferRecord(file.Path, file.Name, 0)
                {
                    State = "已接收", Active = false, BatchId = entry.BatchId, StartedAt = entry.StartedAt
                };
                record.Files.Add(file);
                record.FilesChanged();
                Records.Add(record);
                PublishFiles(record, false);
            }
        }
        catch (Exception error) { Report(error); }
    }
}
