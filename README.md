# File Command Center

Et lille dashboard til at samle adgangen til dine filer (Excel, PDF, billeder, dokumenter, mapper, links – alle typer) ét sted, uanset om de ligger lokalt, på et netværksdrev eller i OneDrive. Dashboardet gemmer kun **stien** til hver fil; filerne flyttes eller kopieres aldrig.

Findes i to udgaver, der deler den samme side (`index.html`):

## Desktop-udgaven (anbefales)

En rigtig Windows-app (.NET 8 + WebView2), uden nogen webserver eller åben port. Se **[desktop/README.md](desktop/README.md)** for byg-instruktioner, hvad appen gør på pc'en, og krav.

## Browser/PowerShell-udgaven

Den oprindelige udgave. Dobbeltklik på `start-dashboard.bat` – den starter en lille lokal hjælper (`dashboard-server.ps1`) på `http://localhost:8787`, som kun kan nås fra din egen pc, og åbner dashboardet i browseren.

## Funktioner

- Filvælger, "Scan mapper…" og en indbygget mappebrowser til at tilføje filer og mapper.
- Hubs, tags, favoritter, arkiv og filstatus (findes/mangler filen).
- Forhåndsvisningsrude (som i Stifinder) med regnearks-/CSV-tabel, billeder, PDF'er og tekst/kode-filer – bredden kan trækkes.
- Åbner filer i det program, Windows har knyttet til dem, og blokerer altid programmer/scripts (`.exe`, `.ps1`, `.js` osv.).
- Daglige backups af dine data, plus en ekstra backup hver gang en gemning ville fjerne filer.
- Desktop-udgaven tjekker selv for nye versioner (GitHub Releases) og kan installere en opdatering med ét klik.
- Dansk/engelsk: sprogknappen nederst i sidebaren skifter hele grænsefladen og manualen. Standard er dansk; vælges automatisk ud fra styresystemets sprog, før dine indstillinger er indlæst.

## Data

Dine data (`data.json` + `backups/`) gemmes lokalt og er **ikke** en del af dette repo:
- Desktop-udgaven: `%LOCALAPPDATA%\FileCommandCenter\`
- Browser-udgaven: i samme mappe som `dashboard-server.ps1`

## Installer

En .msi til desktop-udgaven kan bygges fra `desktop/installer/`, se **[desktop/installer/README.md](desktop/installer/README.md)**. Installerer i `Program Files`, ingen ekstra afhængigheder.

## Ikke gjort endnu

- **Kodesignering.** Installeren er usigneret, så Windows vil advare (SmartScreen/Defender). IT skal godkende eller signere den, før den bredt kan installeres på arbejdscomputere.
- Se `desktop/README.md` og `desktop/installer/README.md` for flere detaljer om, hvad der mangler.
