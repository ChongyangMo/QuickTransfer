using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace QuickTransfer.Services;

public sealed class GalleryFileWatcher : IDisposable
{
    private readonly object sync = new();
    private readonly Dictionary<string, FileSystemWatcher> watchers = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> pendingPaths = new(StringComparer.OrdinalIgnoreCase);
    private readonly Action<IReadOnlyList<string>> onPathsChanged;
    private readonly Action onRescanRequested;
    private readonly Timer debounceTimer;
    private bool rescanRequested;
    private bool disposed;

    public GalleryFileWatcher(Action<IReadOnlyList<string>> onPathsChanged, Action onRescanRequested)
    {
        this.onPathsChanged = onPathsChanged;
        this.onRescanRequested = onRescanRequested;
        debounceTimer = new Timer(FlushPending, null, Timeout.Infinite, Timeout.Infinite);
    }

    public void SyncDirectories(IEnumerable<string> filePaths)
    {
        var desired = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in filePaths)
        {
            if (string.IsNullOrWhiteSpace(path)) continue;
            try
            {
                var directory = Path.GetDirectoryName(Path.GetFullPath(path));
                if (!string.IsNullOrWhiteSpace(directory) && Directory.Exists(directory))
                    desired.Add(directory);
            }
            catch { }
        }

        lock (sync)
        {
            if (disposed) return;
            foreach (var existing in watchers.Keys.Where(dir => !desired.Contains(dir)).ToArray())
            {
                DisposeWatcher(watchers[existing]);
                watchers.Remove(existing);
            }
            foreach (var directory in desired)
            {
                if (watchers.ContainsKey(directory)) continue;
                try
                {
                    var watcher = new FileSystemWatcher(directory)
                    {
                        NotifyFilter = NotifyFilters.FileName,
                        IncludeSubdirectories = false
                    };
                    watcher.Deleted += OnDeleted;
                    watcher.Renamed += OnRenamed;
                    watcher.Error += OnError;
                    watcher.EnableRaisingEvents = true;
                    watchers[directory] = watcher;
                }
                catch { }
            }
        }
    }

    private void OnDeleted(object sender, FileSystemEventArgs args) => EnqueuePath(args.FullPath);

    private void OnRenamed(object sender, RenamedEventArgs args) => EnqueuePath(args.OldFullPath);

    private void OnError(object sender, ErrorEventArgs args)
    {
        lock (sync)
        {
            if (disposed) return;
            rescanRequested = true;
            debounceTimer.Change(150, Timeout.Infinite);
        }
    }

    private void EnqueuePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        lock (sync)
        {
            if (disposed) return;
            try { pendingPaths.Add(Path.GetFullPath(path)); }
            catch { pendingPaths.Add(path); }
            debounceTimer.Change(150, Timeout.Infinite);
        }
    }

    private void FlushPending(object? state)
    {
        string[]? batch = null;
        var rescan = false;
        lock (sync)
        {
            if (disposed) return;
            rescan = rescanRequested;
            rescanRequested = false;
            if (!rescan && pendingPaths.Count > 0)
            {
                batch = pendingPaths.ToArray();
            }
            pendingPaths.Clear();
        }
        if (rescan) onRescanRequested();
        else if (batch != null) onPathsChanged(batch);
    }

    private static void DisposeWatcher(FileSystemWatcher watcher)
    {
        try
        {
            watcher.EnableRaisingEvents = false;
            watcher.Dispose();
        }
        catch { }
    }

    public void Dispose()
    {
        lock (sync)
        {
            if (disposed) return;
            disposed = true;
            debounceTimer.Dispose();
            foreach (var watcher in watchers.Values) DisposeWatcher(watcher);
            watchers.Clear();
            pendingPaths.Clear();
        }
    }
}
