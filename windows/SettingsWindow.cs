using System;
using System.Threading.Tasks;
using System.Windows;
using QuickTransfer.Views;

namespace QuickTransfer;

public partial class MainWindow
{
    private async void OpenSettings(object sender, RoutedEventArgs args)
    {
        if (Model.IsTransferring) { Model.ShowToast("请等待传输结束后再修改设置", false); return; }
        var dialog = new SettingsDialog(this);
        if (dialog.ShowDialog() != true) return;
        if (Model.IsTransferring) { Model.ShowToast("请等待传输结束后再修改设置", false); return; }
        try
        {
            var name = dialog.DeviceAlias;
            var port = Model.Settings.Port;
            var format = dialog.HeicReceiveFormat;
            var destination = dialog.ReceiveDirectory;
            var groupByTime = dialog.GroupGalleryByTime;
            var retentionDays = dialog.CacheRetentionDays;
            var restart = name.Trim() != Model.Settings.Alias;
            var groupingChanged = groupByTime != Model.Settings.GroupGalleryByTime;
            var retentionChanged = retentionDays != Model.Settings.CacheRetentionDays;
            await Task.Run(() => Model.Settings.Save(name, port, format, destination, groupByTime, retentionDays));
            Model.Status = "";
            if (groupingChanged) Model.NotifyGalleryGroupingChanged();
            if (retentionChanged) _ = Model.CleanExpiredOutboxAsync();
            if (restart) Model.Restart();
            Model.ShowToast("设置已保存");
        }
        catch (Exception error) { Model.Report(error); }
    }
}
