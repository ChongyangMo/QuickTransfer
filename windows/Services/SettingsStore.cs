using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using QuickTransfer.Models;

namespace QuickTransfer.Services;

public sealed class SettingsStore
{
    public string Root { get; }
    public JsonObject Values { get; private set; }
    public string Alias => Values["alias"]?.GetValue<string>() ?? Environment.MachineName;
    public int Port => Values["port"]?.GetValue<int>() ?? 53317;
    public string ReceiveDirectory => Values["receiveDirectory"]?.GetValue<string>() is { Length: > 0 } directory
        ? directory : ReceiveDirectories.DefaultDirectory;
    public bool GroupGalleryByTime => Values["galleryGroupByTime"]?.GetValue<bool>() ?? true;
    public HeicReceiveFormat HeicReceiveFormat => Values["heicReceiveFormat"]?.GetValue<string>() switch
    {
        "jpg" => HeicReceiveFormat.Jpg,
        "png" => HeicReceiveFormat.Png,
        _ => HeicReceiveFormat.Original
    };

    public SettingsStore(string? root = null)
    {
        Root = root ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuickTransfer");
        Directory.CreateDirectory(Root);
        var path = Path.Combine(Root, "settings.json");
        Values = File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path))?.AsObject() ?? new() : new();
        if (string.IsNullOrWhiteSpace(Alias)) throw new InvalidDataException("设备名称不能为空");
        if (Port is < 1 or > 65535) throw new InvalidDataException("端口必须为 1 到 65535");
    }

    public void Save(string alias, int port, HeicReceiveFormat heicReceiveFormat, string? receiveDirectory = null)
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
        SaveValues(next);
    }

    public void SaveGalleryGrouping(bool enabled)
    {
        var next = (JsonObject)Values.DeepClone();
        next["galleryGroupByTime"] = enabled;
        SaveValues(next);
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
