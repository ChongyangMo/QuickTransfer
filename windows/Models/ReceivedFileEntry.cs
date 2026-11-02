using System;

namespace QuickTransfer.Models;

public sealed record ReceivedFileEntry(string Path, string BatchId, DateTimeOffset StartedAt);
