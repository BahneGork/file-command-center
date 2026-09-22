# Installer

Bygger en .msi til File Command Center med [WiX Toolset](https://wixtoolset.org/) v5 (**ikke** v6/v7 - de kræver
accept af en betalt "Open Source Maintenance Fee"-EULA, som vi har undgået).

## Hvad den gør

Installerer i `Program Files\File Command Center\` (kræver admin) og opretter en Start-menu-genvej. Ingen
skrivebordsgenvej, ingen registrering af filtyper. `data.json` ligger fortsat i `%LOCALAPPDATA%\FileCommandCenter\`
og påvirkes ikke af installation/afinstallation.

## Byg

```bash
dotnet tool install --global wix --version 5.0.2
wix extension add WixToolset.UI.wixext/5.0.2 -g
```

Byg altid **fra publish-outputtet, med en rigtig Windows-sti som working directory** - WiX's binder bruger Windows
Installer-databaseAPI'et direkte, og det fejler med "The Windows Installer service failed to start" (MSI 1631), hvis
man kører fra en netværks-/UNC-sti (fx `\\wsl.localhost\...`, som er hvad denne mappe ligger på fra WSL). Kopiér
`Package.wxs` og `..\publish\` til en lokal `C:\`-mappe, og byg derfra:

```powershell
dotnet publish ..\CommandCenter.csproj -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true `
  -p:DebugType=none -o C:\build\publish

Copy-Item Package.wxs C:\build\
cd C:\build
wix build Package.wxs -arch x64 -ext WixToolset.UI.wixext -d PublishDir=publish -out FileCommandCenter.msi
```

`msiserver`-tjenesten (Windows Installer) skal køre - den er normalt sat til "Manual" og starter typisk af sig selv,
men start den manuelt (`Start-Service msiserver`), hvis bygningen fejler med MSI 1631.

## Ny version

**`UpgradeCode` i `Package.wxs` (`dc319aa0-1725-4cc3-8c86-3dbd4fb3a308`) må aldrig ændres** - det er det, der lader en
nyere version opdatere en ældre i stedet for at installere ved siden af den. Sæt kun `Version` op ved en ny udgivelse.

## Ikke gjort endnu

- **Signering.** MSI'en er usigneret, så Windows SmartScreen/Defender vil advare, og virksomhedens IT skal
  sandsynligvis godkende eller signere den, før den kan installeres på arbejdscomputere. Se overvejelserne i
  `../README.md`.
- Ingen skrivebordsgenvej eller "Reparér/Afinstallér"-genvej i Start-menuen ud over standard Windows-håndtering
  (Indstillinger → Apps).
