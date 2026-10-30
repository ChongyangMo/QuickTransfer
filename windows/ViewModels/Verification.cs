using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using System.Threading.Tasks;

namespace QuickTransfer.ViewModels;

public sealed partial class MainViewModel
{
    private JsonObject? verification;
    private Channel<string>? verificationLog;
    private Task? verificationWriter;
    private int verificationStep;
    private bool verificationSending;

    public void ConfigureVerification(string path)
    {
        verification = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        var logPath = verification["logPath"]?.GetValue<string>() ?? Path.Combine(Settings.Root, "verification.jsonl");
        var writer = new StreamWriter(logPath, false) { AutoFlush = true };
        verificationLog = Channel.CreateUnbounded<string>(new UnboundedChannelOptions { SingleReader = true, SingleWriter = true });
        verificationWriter = Task.Run(async () =>
        {
            await using (writer)
                await foreach (var line in verificationLog.Reader.ReadAllAsync()) await writer.WriteLineAsync(line);
        });
    }

    public bool VerifyReceive(JsonElement value) => verification?["receiveFingerprint"]?.GetValue<string>() == String(value, "peer");

    private void VerifyEvent(JsonElement value)
    {
        if (verification == null) return;
        verificationLog!.Writer.TryWrite(value.GetRawText());
        var type = String(value, "type");
        if (type == "ready" && verification["host"] is JsonValue host)
            Probe(host.GetValue<string>(), verification["port"]?.GetValue<int>() ?? 53317);
        if (type == "sent") { verificationSending = false; verificationStep++; }
        if (type is not ("devices" or "sent") || verificationSending || verification["sendFingerprint"] == null) return;
        var expected = verification["sendFingerprint"]!.GetValue<string>();
        if (!Devices.Any(peer => peer.Id == expected) || verification["transfers"] is not JsonArray transfers || verificationStep >= transfers.Count) return;
        var payload = (JsonObject)transfers[verificationStep]!.DeepClone();
        payload["action"] = "send";
        payload["peer"] = expected;
        core.Send(payload);
        verificationSending = true;
    }

    public async Task CloseVerificationAsync()
    {
        verificationLog?.Writer.TryComplete();
        if (verificationWriter != null) await verificationWriter;
    }
}
