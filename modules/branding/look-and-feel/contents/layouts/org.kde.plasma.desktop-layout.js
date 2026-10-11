// ANKA desktop: a slim bar at the top, a floating dock at the bottom.
// Plasma runs this once, the first time a user logs in.

// ── Wallpaper ────────────────────────────────────────────────────────────
var desktops = desktopsForActivity(currentActivity());
for (var i = 0; i < desktops.length; i++) {
    desktops[i].wallpaperPlugin = "org.kde.image";
    desktops[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktops[i].writeConfig("Image", "file:///run/current-system/sw/share/wallpapers/ANKA/");
}

// ── Top bar: ANKA menu on the left, status and clock on the right ────────
var bar = new Panel;
bar.location = "top";
bar.height = 2 * Math.ceil(gridUnit * 1.6 / 2);
bar.floating = false;

var menu = bar.addWidget("org.kde.plasma.kickoff");
menu.currentConfigGroup = ["General"];
menu.writeConfig("icon", "anka-symbolic");

bar.addWidget("org.kde.plasma.panelspacer");
bar.addWidget("org.kde.plasma.systemtray");
bar.addWidget("org.kde.plasma.digitalclock");

// ── Dock: favourite apps and open windows, centred ───────────────────────
var dock = new Panel;
dock.location = "bottom";
dock.height = 2 * Math.ceil(gridUnit * 2.6 / 2);
dock.floating = true;
dock.lengthMode = "fit";
dock.alignment = "center";
dock.hiding = "none";

// Only apps this installation has (the light profile has no Steam).
var favourites = [
    "org.kde.dolphin.desktop",
    defaultApplication("browser", true) || "firefox.desktop",
    "org.kde.discover.desktop",
    "steam.desktop",
    "systemsettings.desktop",
];
var launchers = [];
for (var j = 0; j < favourites.length; j++) {
    if (applicationExists(favourites[j])) {
        launchers.push("applications:" + favourites[j]);
    }
}

var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", launchers);
