using System.Globalization;
using System.Text.Json;

namespace CommandCenter;

sealed class ApiError(string message) : Exception(message);

// The app's own messages follow the language chosen on the page, which is sent with every call (see MainForm).
// Before the page has loaded, the saved choice is used, or else the Windows language, the same way the page picks it.
static class L
{
    public static bool En = Store.SavedLang() is { } lang ? lang == "en" : CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "en";
    public static string T(string da, string en) => En ? en : da;
}

// The same "routes" the PowerShell helper had, but called through messages from the page (no network port)
static class Api
{
    static string Str(JsonElement b, string k) => b.ValueKind == JsonValueKind.Object && b.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : "";
    static bool Bool(JsonElement b, string k) => b.ValueKind == JsonValueKind.Object && b.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.True;
    static int Int(JsonElement b, string k) => b.ValueKind == JsonValueKind.Object && b.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : 0;
    static string Json(object o) => JsonSerializer.Serialize(o);

    static void RequireRegistered(string p)
    {
        if (!Store.IsRegistered(p)) throw new ApiError(L.T("Stien er ikke registreret i dashboardet", "The path is not registered on the dashboard"));
    }

    // Returns the reply as JSON text. onProgress is only used by /api/update/install to report download progress along the way.
    public static async Task<string> Handle(string path, JsonElement body, IWin32Window owner, Action<long, long>? onProgress = null)
    {
        switch (path)
        {
            case "/api/ping":
                return "{\"ok\":true}";

            case "/api/info":
                return Json(new { version = UpdateCheck.CurrentVersion.ToString(3), portable = UpdateCheck.IsPortable });

            case "/api/state":
                if (body.ValueKind == JsonValueKind.Object) { Store.Save(body.GetRawText()); return "{\"ok\":true}"; }
                return Store.Load() ?? "null";

            case "/api/open":
            {
                var p = Str(body, "path");
                RequireRegistered(p);
                FileOps.Open(p, Bool(body, "reveal"));
                return "{\"ok\":true}";
            }

            case "/api/file":
            {
                var p = Str(body, "path");
                RequireRegistered(p);
                return Json(await Task.Run(() => FileOps.ReadFile(p, Int(body, "max"))));
            }

            case "/api/check":
            {
                var paths = body.TryGetProperty("paths", out var arr) && arr.ValueKind == JsonValueKind.Array
                    ? arr.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!) : [];
                return Json(new { results = await FileOps.Check(paths) });
            }

            case "/api/ls":
                return Json(await Task.Run(() => FileOps.ListDir(Str(body, "path"), Bool(body, "all"))));

            case "/api/scan":
                return Json(await Task.Run(() => FileOps.Scan(Str(body, "folder"), Bool(body, "recurse"))));

            case "/api/find":
            {
                var names = body.TryGetProperty("names", out var arr) && arr.ValueKind == JsonValueKind.Array
                    ? arr.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!).ToList() : [];
                return Json(await Task.Run(() => FileOps.Find(Str(body, "folder"), names)));
            }

            case "/api/pick":
            {
                using var dlg = new OpenFileDialog
                {
                    Multiselect = Bool(body, "multi"),
                    Title = L.T("Vælg filer til dashboardet", "Choose files for the dashboard"),
                    Filter = L.T("Alle filer", "All files") + "|*.*|" + L.T("Excel og CSV", "Excel and CSV") + "|*.xlsx;*.xlsm;*.xlsb;*.xls;*.csv",
                };
                return Json(new { paths = dlg.ShowDialog(owner) == DialogResult.OK ? dlg.FileNames : [] });
            }

            case "/api/pickfolder":
            {
                using var dlg = new FolderBrowserDialog { Description = L.T("Vælg en mappe", "Choose a folder") };
                return Json(new { path = dlg.ShowDialog(owner) == DialogResult.OK ? dlg.SelectedPath : null });
            }

            case "/api/update/check":
            {
                var info = await UpdateCheck.CheckAsync();
                return info is null
                    ? "{\"available\":false}"
                    : Json(new { available = true, version = info.Version, notes = info.Notes, url = info.HtmlUrl, size = info.AssetSize });
            }

            case "/api/update/install":
            {
                var info = await UpdateCheck.CheckAsync();
                if (info is null) throw new ApiError(L.T("Ingen opdatering fundet - prøv at tjekke igen.", "No update found - try checking again."));
                await UpdateCheck.DownloadAndLaunchInstallerAsync(info, (received, total) => onProgress?.Invoke(received, total));
                return "{\"ok\":true}";
            }

            default:
                throw new ApiError(L.T("Ikke fundet", "Not found"));
        }
    }
}
