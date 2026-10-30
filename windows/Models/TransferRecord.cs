using System;
using System.Collections.ObjectModel;
using QuickTransfer.Infrastructure;

namespace QuickTransfer.Models;

public sealed class TransferRecord(string id, string name, double size) : ObservableObject
{
    public string Id { get; } = id;
    public string Name { get; } = name;
    public double Size { get; } = size;
    public string BatchId { get; init; } = id;
    public DateTimeOffset StartedAt { get; init; } = DateTimeOffset.Now;
    public ObservableCollection<Attachment> Files { get; } = new();
    public string Text { get; init; } = "";
    public bool HasText => Text.Length > 0;
    public bool HasFiles => Files.Count > 0;
    private string state = "传输中";
    private double progress;
    private bool active = true;
    public string State { get => state; set => Set(ref state, value); }
    public double Progress { get => progress; set => Set(ref progress, value); }
    public bool Active { get => active; set => Set(ref active, value); }
    public void FilesChanged() => Notify(nameof(HasFiles));
}
