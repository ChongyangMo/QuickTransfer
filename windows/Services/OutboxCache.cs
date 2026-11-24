using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace QuickTransfer.Services;

public readonly record struct CacheStats(int Count, long TotalBytes);

public static class OutboxCache
{
    public static string DirectoryPath(string root) => Path.Combine(root, "outbox");

    public static CacheStats Measure(string root)
    {
        var directory = DirectoryPath(root);
        if (!Directory.Exists(directory)) return new CacheStats(0, 0);
        var count = 0;
        long total = 0;
        try
        {
            foreach (var file in new DirectoryInfo(directory).EnumerateFiles("*", new EnumerationOptions
                     { RecurseSubdirectories = true, IgnoreInaccessible = true }))
            {
                count++;
                total += file.Length;
            }
        }
        catch { }
        return new CacheStats(count, total);
    }

    public static (int RemovedCount, HashSet<string> RemovedPaths) CleanExpired(
        string root, int retentionDays, IReadOnlySet<string> protectedPaths)
    {
        var cutoff = DateTime.UtcNow.AddDays(-Math.Clamp(retentionDays, 1, 365));
        return CleanMatching(root, protectedPaths, file => file.LastWriteTimeUtc < cutoff);
    }

    public static (int RemovedCount, HashSet<string> RemovedPaths) ClearAll(
        string root, IReadOnlySet<string> protectedPaths) =>
        CleanMatching(root, protectedPaths, _ => true);

    private static (int RemovedCount, HashSet<string> RemovedPaths) CleanMatching(
        string root, IReadOnlySet<string> protectedPaths, Func<FileInfo, bool> shouldDelete)
    {
        var directory = DirectoryPath(root);
        var removed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (!Directory.Exists(directory)) return (0, removed);
        try
        {
            var files = new DirectoryInfo(directory).EnumerateFiles("*", new EnumerationOptions
            {
                RecurseSubdirectories = true,
                IgnoreInaccessible = true
            }).ToArray();
            foreach (var file in files)
            {
                var full = Path.GetFullPath(file.FullName);
                if (protectedPaths.Contains(full)) continue;
                if (!shouldDelete(file)) continue;
                try
                {
                    file.Delete();
                    removed.Add(full);
                }
                catch { }
            }
            PruneEmptyDirectories(directory);
        }
        catch { }
        return (removed.Count, removed);
    }

    private static void PruneEmptyDirectories(string rootDirectory)
    {
        try
        {
            var dirs = Directory.GetDirectories(rootDirectory, "*", SearchOption.AllDirectories)
                .OrderByDescending(path => path.Length);
            foreach (var dir in dirs)
            {
                try
                {
                    if (!Directory.EnumerateFileSystemEntries(dir).Any())
                        Directory.Delete(dir);
                }
                catch { }
            }
        }
        catch { }
    }
}
