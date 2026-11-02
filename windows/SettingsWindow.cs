using System;
using System.Windows;
using QuickTransfer.Models;
using QuickTransfer.Services;
using QuickTransfer.Views;

namespace QuickTransfer;

public partial class MainWindow
{
    private async void OpenSettings(object sender, RoutedEventArgs args)
    {
        if (Model.IsTransferring) { Model.Status = "请等待传输结束后再修改设置"; return; }
        var dialog = new PromptWindow(this, "设置", "保存");
        var alias = dialog.AddField("设备名称", Model.Settings.Alias);
        var port = dialog.AddField("端口", Model.Settings.Port.ToString());
        var directory = dialog.AddFolderField("保存目录", Model.Settings.ReceiveDirectory);
        var heicFormat = dialog.AddSelect("接收 HEIC", new[] { "保留原格式", "转为 JPG", "转为 PNG" }, (int)Model.Settings.HeicReceiveFormat);
        dialog.Validate = () =>
        {
            if (string.IsNullOrWhiteSpace(alias.Text) || !ValidPort(port.Text)) return "请输入设备名称和有效端口";
            try { ReceiveDirectories.EnsureWritable(directory.Text); return ""; }
            catch (Exception error) { return "保存目录不可用：" + error.Message; }
        };
        if (dialog.ShowDialog() != true) return;
        if (Model.IsTransferring) { Model.Status = "请等待传输结束后再修改设置"; return; }
        try
        {
            var name = alias.Text;
            var number = int.Parse(port.Text);
            var format = (HeicReceiveFormat)heicFormat.SelectedIndex;
            var destination = directory.Text;
            var restart = name.Trim() != Model.Settings.Alias || number != Model.Settings.Port;
            await System.Threading.Tasks.Task.Run(() => Model.Settings.Save(name, number, format, destination));
            Model.Status = "";
            if (restart) Model.Restart();
        }
        catch (Exception error) { Model.Report(error); }
    }
}
