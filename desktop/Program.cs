namespace CommandCenter;

static class Program
{
    [STAThread]
    static void Main()
    {
        // Kun ét vindue ad gangen, så to kopier ikke overskriver hinandens data
        using var single = new Mutex(true, @"Local\FileCommandCenter", out var first);
        if (!first)
        {
            MessageBox.Show("File Command Center kører allerede.", "File Command Center", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}
