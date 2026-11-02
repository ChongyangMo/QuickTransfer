using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using QuickTransfer.Models;

namespace QuickTransfer.Services;

public sealed class ReceivedFileStore(string root)
{
    private readonly SemaphoreSlim gate = new(1);
    private readonly string historyPath = Path.Combine(root, "received-files.json");
    private List<ReceivedFileEntry>? history;

    public async Task<string> StoreAsync(string source, string directory, string batchId, DateTimeOffset startedAt)
    {
        await gate.WaitAsync();
        try
        {
            return await Task.Run(() =>
            {
                LoadHistory();
                directory = ReceiveDirectories.Normalize(directory);
                Directory.CreateDirectory(directory);
                source = Path.GetFullPath(source);
                var name = Path.GetFileNameWithoutExtension(source);
                var extension = Path.GetExtension(source);
                var target = Path.Combine(directory, Path.GetFileName(source));
                var moved = !string.Equals(source, target, StringComparison.OrdinalIgnoreCase);
                if (moved)
                {
                    // 不覆盖已有文件，也兼容同时接收多个同名文件。
                    for (var suffix = 2; ; suffix++)
                    {
                        try { File.Move(source, target); break; }
                        catch (IOException) when (File.Exists(target))
                        { target = Path.Combine(directory, $"{name} ({suffix}){extension}"); }
                    }
                }
                var entry = new ReceivedFileEntry(target, batchId, startedAt);
                history!.Add(entry);
                try { SaveHistory(); }
                catch
                {
                    history.Remove(entry);
                    if (moved) File.Move(target, source);
                    throw;
                }
                return target;
            });
        }
        finally { gate.Release(); }
    }

    public async Task<ReceivedFileEntry[]> ReadAsync()
    {
        await gate.WaitAsync();
        try
        {
            return await Task.Run(() =>
            {
                LoadHistory();
                var entries = history!.Where(entry => File.Exists(entry.Path)).ToList();
                var legacy = Path.Combine(root, "received");
                if (Directory.Exists(legacy))
                {
                    foreach (var file in new DirectoryInfo(legacy).EnumerateFiles("*", new EnumerationOptions
                        { RecurseSubdirectories = true, IgnoreInaccessible = true }))
                    {
                        if (file.Extension.Equals(".part", StringComparison.OrdinalIgnoreCase)) continue;
                        var batch = Path.GetRelativePath(legacy, file.FullName).Split(Path.DirectorySeparatorChar)[0];
                        var batchDirectory = Path.Combine(legacy, batch);
                        entries.Add(new ReceivedFileEntry(file.FullName, batch,
                            new DateTimeOffset(Directory.GetCreationTimeUtc(batchDirectory))));
                    }
                }
                return entries.DistinctBy(entry => entry.Path, StringComparer.OrdinalIgnoreCase)
                    .OrderByDescending(entry => entry.StartedAt).Take(30).ToArray();
            });
        }
        finally { gate.Release(); }
    }

    private void LoadHistory() => history ??= File.Exists(historyPath)
        ? JsonSerializer.Deserialize<List<ReceivedFileEntry>>(File.ReadAllText(historyPath)) ?? new()
        : new();

    private void SaveHistory()
    {
        var temporary = historyPath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(history));
        File.Move(temporary, historyPath, true);
    }
}
