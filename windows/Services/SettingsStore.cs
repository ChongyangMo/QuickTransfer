using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace QuickTransfer.Services;

public sealed class SettingsStore
{
    public string Root { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuickTransfer");
    public JsonObject Values { get; private set; }
    public string Alias => Values["alias"]?.GetValue<string>() ?? Environment.MachineName;
    public int Port => Values["port"]?.GetValue<int>() ?? 53317;
    public bool GroupGalleryByTime => Values["galleryGroupByTime"]?.GetValue<bool>() ?? true;

    public SettingsStore()
    {
        Directory.CreateDirectory(Root);
        var path = Path.Combine(Root, "settings.json");
        Values = File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path))?.AsObject() ?? new() : new();
        if (string.IsNullOrWhiteSpace(Alias)) throw new InvalidDataException("设备名称不能为空");
        if (Port is < 1 or > 65535) throw new InvalidDataException("端口必须为 1 到 65535");
    }

    public void Save(string alias, int port)
    {
        var next = (JsonObject)Values.DeepClone();
        next["alias"] = alias.Trim();
        next["port"] = port;
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
