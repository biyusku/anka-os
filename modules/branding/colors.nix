# ANKA colour scheme: neutral graphite greys (no blue tint) with ANKA's red.
# Installed as share/color-schemes/ANKA.colors and written into
# /etc/xdg/kdeglobals, so apps are ANKA-coloured from the first login.
let
  text      = "245,245,247";
  secondary = "152,152,157";
  accent    = "192,57,43";     # #c0392b, docs/branding.md
  focus     = "231,76,60";     # lighter red: focus rings stay visible on grey
  link      = "243,156,18";    # ANKA gold
  states = {
    DecorationFocus    = focus;
    DecorationHover    = focus;
    ForegroundActive   = focus;
    ForegroundInactive = secondary;
    ForegroundLink     = link;
    ForegroundNegative = "237,85,101";
    ForegroundNeutral  = "246,142,48";
    ForegroundNormal   = text;
    ForegroundPositive = "52,199,89";
    ForegroundVisited  = "175,130,215";
  };
  surface = normal: alternate: states // {
    BackgroundNormal    = normal;
    BackgroundAlternate = alternate;
  };
in
{
  inherit accent;

  scheme = {
    "ColorEffects:Disabled" = {
      Color = "56,56,56";
      ColorAmount = 0;
      ColorEffect = 0;
      ContrastAmount = "0.65";
      ContrastEffect = 1;
      IntensityAmount = "0.1";
      IntensityEffect = 2;
    };
    "ColorEffects:Inactive" = {
      ChangeSelectionColor = true;
      Color = "112,111,110";
      ColorAmount = "0.025";
      ColorEffect = 2;
      ContrastAmount = "0.1";
      ContrastEffect = 2;
      Enable = false;
      IntensityAmount = 0;
      IntensityEffect = 0;
    };

    "Colors:Window"          = surface "30,30,30" "40,40,42";
    "Colors:View"            = surface "22,22,22" "30,30,30";
    "Colors:Button"          = surface "50,50,52" "62,62,64";
    "Colors:Header"          = surface "38,38,40" "30,30,30";
    "Colors:Header][Inactive" = surface "30,30,30" "38,38,40";
    "Colors:Tooltip"         = surface "44,44,46" "38,38,40";
    "Colors:Complementary"   = surface "18,18,18" "30,30,30";
    "Colors:Selection"       = surface accent "120,36,27" // {
      ForegroundActive   = "255,255,255";
      ForegroundInactive = "235,200,195";
      ForegroundLink     = "253,188,75";
      ForegroundNormal   = "255,255,255";
    };

    General = {
      ColorScheme = "ANKA";
      Name = "ANKA";
      shadeSortColumn = true;
    };
    KDE.contrast = 4;
    WM = {
      activeBackground   = "38,38,40";
      activeBlend        = text;
      activeForeground   = text;
      inactiveBackground = "30,30,30";
      inactiveBlend      = secondary;
      inactiveForeground = secondary;
    };
  };
}
