using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using QuickTransfer.Services;

namespace QuickTransfer.Views;

public sealed class PromptWindow : Window
{
    private readonly StackPanel fields = new();
    private readonly TextBlock error = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0), Visibility = Visibility.Collapsed };
    public Func<string>? Validate { get; set; }

    public PromptWindow(Window owner, string title, string confirm, string cancel = "取消")
    {
        Owner = owner;
        Title = title;
        Width = 370;
        MaxHeight = 620;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        FontFamily = owner.FontFamily;
        FontSize = owner.FontSize;
        SetResourceReference(BackgroundProperty, "PageBrush");
        SetResourceReference(ForegroundProperty, "TextBrush");
        var root = new StackPanel { Margin = new Thickness(20) };
        root.Children.Add(fields);
        error.SetResourceReference(TextBlock.ForegroundProperty, "DangerBrush");
        root.Children.Add(error);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 20, 0, 0) };
        var close = new Button { Content = cancel, IsCancel = true, Height = 34, Margin = new Thickness(0, 0, 8, 0) };
        var accept = new Button { Content = confirm, IsDefault = true, Height = 34, Style = (Style)FindResource("PrimaryButton") };
        accept.Click += (_, _) =>
        {
            var message = Validate?.Invoke() ?? "";
            if (message.Length > 0) { error.Text = message; error.Visibility = Visibility.Visible; return; }
            DialogResult = true;
        };
        buttons.Children.Add(close);
        buttons.Children.Add(accept);
        root.Children.Add(buttons);
        Content = root;
        ThemeManager.Attach(this);
    }

    public TextBox AddField(string label, string value)
    {
        fields.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, fields.Children.Count == 0 ? 0 : 14, 0, 6) });
        var field = new TextBox { Text = value, Height = 34 };
        System.Windows.Automation.AutomationProperties.SetName(field, label);
        fields.Children.Add(field);
        if (fields.Children.Count == 2) Loaded += (_, _) => { field.Focus(); field.SelectAll(); };
        return field;
    }

    public void AddPreview(string text)
    {
        var preview = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap };
        fields.Children.Add(new ScrollViewer { Content = preview, MaxHeight = 280, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
    }

    public TextBox AddFolderField(string label, string value)
    {
        var field = AddField(label, value);
        fields.Children.Remove(field);
        var row = new DockPanel();
        var browse = new Button { Content = "选择…", Height = 34, Margin = new Thickness(8, 0, 0, 0) };
        System.Windows.Automation.AutomationProperties.SetName(browse, "选择" + label);
        browse.Click += (_, _) =>
        {
            var picker = new OpenFolderDialog { Title = "选择" + label, InitialDirectory = Directory.Exists(field.Text) ? field.Text : Path.GetDirectoryName(value) };
            if (picker.ShowDialog(this) == true) { field.Text = picker.FolderName; field.CaretIndex = field.Text.Length; }
        };
        DockPanel.SetDock(browse, Dock.Right);
        row.Children.Add(browse);
        row.Children.Add(field);
        fields.Children.Add(row);
        return field;
    }

    public ComboBox AddSelect(string label, IReadOnlyList<string> options, int selectedIndex)
    {
        fields.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, fields.Children.Count == 0 ? 0 : 14, 0, 6) });
        var select = new ComboBox
        {
            ItemsSource = options,
            SelectedIndex = selectedIndex,
            Height = 34,
            Style = (Style)FindResource("Select")
        };
        System.Windows.Automation.AutomationProperties.SetName(select, label);
        fields.Children.Add(select);
        return select;
    }

    public CheckBox AddCheckBox(string label)
    {
        var check = new CheckBox { Content = label, Margin = new Thickness(0, 16, 0, 0) };
        fields.Children.Add(check);
        return check;
    }
}
