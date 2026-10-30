using System;
using System.Windows;
using System.Windows.Controls;
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

    public CheckBox AddCheckBox(string label)
    {
        var check = new CheckBox { Content = label, Margin = new Thickness(0, 16, 0, 0) };
        fields.Children.Add(check);
        return check;
    }
}
