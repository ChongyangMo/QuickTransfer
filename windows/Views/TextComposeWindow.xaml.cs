using System.Windows;
using System.Windows.Input;
using QuickTransfer.Services;

namespace QuickTransfer.Views;

public partial class TextComposeWindow : Window
{
    private readonly MainWindow main;
    public TextComposeWindow(MainWindow owner)
    {
        main = owner;
        Owner = owner;
        InitializeComponent();
        DataContext = owner.Model;
        ThemeManager.Attach(this);
        DataObject.AddPastingHandler(Composer, (_, args) =>
        {
            if (!args.DataObject.GetDataPresent(DataFormats.FileDrop) && !args.DataObject.GetDataPresent(DataFormats.Bitmap)) return;
            args.CancelCommand();
            _ = main.PasteAsync();
        });
    }
    public void FocusEditor() => Composer.Focus();
    private async void Paste(object sender, RoutedEventArgs args) => await main.PasteAsync();
    private void OnKeyDown(object sender, KeyEventArgs args)
    {
        if (args.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.Control)
        { main.Model.SendCommand.Execute(null); args.Handled = true; }
        else if (args.Key == Key.Escape) Close();
    }
}
