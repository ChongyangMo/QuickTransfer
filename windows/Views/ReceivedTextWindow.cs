using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using QuickTransfer.Services;

namespace QuickTransfer.Views;

public sealed class ReceivedTextWindow : Window
{
    public ReceivedTextWindow(MainWindow owner, string alias, string text)
    {
        var attachToOwner = owner.IsVisible && owner.WindowState != WindowState.Minimized;
        if (attachToOwner) Owner = owner;
        Title = string.IsNullOrEmpty(alias) ? "收到文字" : alias;
        Width = 480;
        Height = 340;
        MinWidth = 320;
        MinHeight = 220;
        WindowStartupLocation = attachToOwner ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen;
        FontFamily = owner.FontFamily;
        FontSize = owner.FontSize;
        SetResourceReference(BackgroundProperty, "PageBrush");
        SetResourceReference(ForegroundProperty, "TextBrush");
        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition());
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var contents = new TextBox { Text = text, IsReadOnly = true, Margin = new Thickness(14), Style = (Style)FindResource("Composer") };
        contents.SetResourceReference(BackgroundProperty, "PageBrush");
        System.Windows.Automation.AutomationProperties.SetName(contents, "收到的文字");
        grid.Children.Add(contents);
        var strip = new Border { BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(14, 6, 14, 6) };
        strip.SetResourceReference(Border.BorderBrushProperty, "BorderBrush");
        Grid.SetRow(strip, 1);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var close = new Button { Content = "关闭", Style = (Style)FindResource("FlatSendButton"), Margin = new Thickness(0, 0, 12, 0) };
        close.Click += (_, _) => Close();
        var copy = new Button { Content = "复制", Style = (Style)FindResource("FlatSendButton") };
        copy.Click += (_, _) =>
        {
            try { Clipboard.SetText(text); }
            catch (Exception error) { owner.Model.Report(error); }
        };
        buttons.Children.Add(close);
        buttons.Children.Add(copy);
        strip.Child = buttons;
        grid.Children.Add(strip);
        Content = grid;
        PreviewKeyDown += (_, args) => { if (args.Key == Key.Escape) Close(); };
        ThemeManager.Attach(this);
    }
}
