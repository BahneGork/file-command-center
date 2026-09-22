using System.Text.Json;

namespace CommandCenter;

sealed class ApiError(string message) : Exception(message);

// De samme "ruter" som PowerShell-hjælperen havde, men kaldt via beskeder fra siden (ingen netværksport)
static class Api
{
    static string Str(JsonElement b, string k) => b.ValueKind == JsonValueKind.Object && b.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : "";
    static bool Bool(JsonElement b, string k) => b.ValueKind == JsonValueKind.Object && b.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.True;
    static int Int(JsonElement b, string k) => b.ValueKind == JsonValueKind.Object && b.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : 0;
    static string Json(object o) => JsonSerializer.Serialize(o);

    static void RequireRegistered(string p)
    {
        if (!Store.IsRegistered(p)) throw new ApiError("Stien er ikke registreret i dashboardet");
    }

    // Returnerer svaret som JSON-tekst
    public static async Task<string> Handle(string path, JsonElement body, IWin32Window owner)
    {
        switch (path)
        {
            case "/api/ping":
                return "{\"ok\":true}";

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

            case "/api/pick":
            {
                using var dlg = new OpenFileDialog
                {
                    Multiselect = Bool(body, "multi"),
                    Title = "Vælg filer til dashboardet",
                    Filter = "Alle filer|*.*|Excel og CSV|*.xlsx;*.xlsm;*.xlsb;*.xls;*.csv",
                };
                return Json(new { paths = dlg.ShowDialog(owner) == DialogResult.OK ? dlg.FileNames : [] });
            }

            case "/api/pickfolder":
            {
                using var dlg = new FolderBrowserDialog { Description = "Vælg en mappe" };
                return Json(new { path = dlg.ShowDialog(owner) == DialogResult.OK ? dlg.SelectedPath : null });
            }

            default:
                throw new ApiError("Ikke fundet");
        }
    }
}
