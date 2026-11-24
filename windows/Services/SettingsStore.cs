using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using QuickTransfer.Models;

namespace QuickTransfer.Services;

public sealed record CachedPeer(string Id, string Alias, bool Mobile);

public sealed class SettingsStore
{
    private readonly object sync = new();
    public string Root { get; }
    public JsonObject Values { get; private set; }
    public string Alias => Values["alias"]?.GetValue<string>() ?? Environment.MachineName;
    public int Port => Values["port"]?.GetValue<int>() ?? 53317;
    public string ReceiveDirectory => Values["receiveDirectory"]?.GetValue<string>() is { Length: > 0 } directory
        ? directory : ReceiveDirectories.DefaultDirectory;
    public bool GroupGalleryByTime => Values["galleryGroupByTime"]?.GetValue<bool>() ?? true;
    public int CacheRetentionDays => Math.Clamp(Values["cacheRetentionDays"]?.GetValue<int>() ?? 7, 1, 365);
    public string LastPeerId => Values["lastPeerId"]?.GetValue<string>() ?? "";
    public HeicReceiveFormat HeicReceiveFormat => Values["heicReceiveFormat"]?.GetValue<string>() switch
    {
        "jpg" => HeicReceiveFormat.Jpg,
        "png" => HeicReceiveFormat.Png,
        _ => HeicReceiveFormat.Original
    };

    public HashSet<string> ReadPinnedPaths()
    {
        lock (sync)
        {
            var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (Values["pinnedFiles"] is JsonArray items)
            {
                foreach (var node in items)
                {
                    var value = node?.GetValue<string>();
                    if (!string.IsNullOrWhiteSpace(value)) result.Add(Path.GetFullPath(value));
                }
            }
            return result;
        }
    }

    public SettingsStore(string? root = null)
    {
        Root = root ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuickTransfer");
        Directory.CreateDirectory(Root);
        var path = Path.Combine(Root, "settings.json");
        Values = File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path))?.AsObject() ?? new() : new();
        if (string.IsNullOrWhiteSpace(Alias)) throw new InvalidDataException("设备名称不能为空");
        if (Port is < 1 or > 65535) throw new InvalidDataException("端口必须为 1 到 65535");
    }

    public void Save(
        string alias,
        int port,
        HeicReceiveFormat heicReceiveFormat,
        string? receiveDirectory = null,
        bool? groupGalleryByTime = null,
        int? cacheRetentionDays = null)
    {
        lock (sync)
        {
            var next = (JsonObject)Values.DeepClone();
            next["alias"] = alias.Trim();
            next["port"] = port;
            next["receiveDirectory"] = ReceiveDirectories.EnsureWritable(receiveDirectory ?? ReceiveDirectory);
            next["heicReceiveFormat"] = heicReceiveFormat switch
            {
                HeicReceiveFormat.Original => "original",
                HeicReceiveFormat.Jpg => "jpg",
                HeicReceiveFormat.Png => "png",
                _ => throw new ArgumentOutOfRangeException(nameof(heicReceiveFormat))
            };
            if (groupGalleryByTime.HasValue) next["galleryGroupByTime"] = groupGalleryByTime.Value;
            if (cacheRetentionDays.HasValue) next["cacheRetentionDays"] = Math.Clamp(cacheRetentionDays.Value, 1, 365);
            SaveValues(next);
        }
    }

    public void SaveGalleryGrouping(bool enabled)
    {
        lock (sync)
        {
            var next = (JsonObject)Values.DeepClone();
            next["galleryGroupByTime"] = enabled;
            SaveValues(next);
        }
    }

    public void SaveLastPeer(string peerId)
    {
        lock (sync)
        {
            var trimmed = peerId.Trim();
            if (string.Equals(LastPeerId, trimmed, StringComparison.Ordinal)) return;
            var next = (JsonObject)Values.DeepClone();
            next["lastPeerId"] = trimmed;
            SaveValues(next);
        }
    }

    public void SavePinnedPaths(IEnumerable<string> paths)
    {
        lock (sync)
        {
            var array = new JsonArray();
            foreach (var path in paths.Where(item => !string.IsNullOrWhiteSpace(item))
                         .Select(Path.GetFullPath)
                         .Distinct(StringComparer.OrdinalIgnoreCase))
            {
                array.Add(path);
            }
            var next = (JsonObject)Values.DeepClone();
            next["pinnedFiles"] = array;
            SaveValues(next);
        }
    }

    public CachedPeer[] ReadRecentPeers()
    {
        try
        {
            var path = Path.Combine(Root, "last-peers.json");
            if (!File.Exists(path)) return Array.Empty<CachedPeer>();
            return JsonSerializer.Deserialize<CachedPeer[]>(File.ReadAllText(path)) ?? Array.Empty<CachedPeer>();
        }
        catch { return Array.Empty<CachedPeer>(); }
    }

    public void SaveRecentPeers(IEnumerable<CachedPeer> peers)
    {
        try
        {
            var path = Path.Combine(Root, "last-peers.json");
            var temporary = path + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(peers.ToArray()));
            File.Move(temporary, path, true);
        }
        catch { }
    }

    private void SaveValues(JsonObject next)
    {
        var path = Path.Combine(Root, "settings.json");
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, next.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, path, true);
        Values = next;
    }

    public string CoreConfiguration()
    {
        lock (sync)
        {
            var config = (JsonObject)Values.DeepClone();
            config["root"] = Root;
            config["alias"] = Alias;
            config["port"] = Port;
            config["model"] = "Windows";
            config["mobile"] = false;
            config["multicast"] = true;
            return config.ToJsonString();
        }
    }
}
