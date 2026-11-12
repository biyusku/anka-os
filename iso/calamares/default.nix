# ANKA OS — the ANKA installer (Calamares) on the live ISO.
#
# nixpkgs' `calamares-nixos` installs plain NixOS and always reads its own
# settings first, so ANKA ships its own wrapped Calamares instead: ANKA's
# settings, branding and the `ankainstall` job, with the NixOS extension's
# configs as fallback (locale, keyboard, finished pages).
{ lib, pkgs, inputs, ... }:

let
  self      = inputs.self;
  nixosExt  = pkgs.calamares-nixos-extensions;
  flakeRepo = { type = "github"; owner = "biyusku"; repo = "anka-os"; };

  # /etc/nixos/flake.lock for installed machines: ANKA pinned to the revision
  # this ISO is built from, plus ANKA's own pinned inputs. Follows paths in a
  # lock file are relative to its root, so ANKA's lock moves under an `anka`
  # node. Without a clean git revision the installer falls back to
  # --override-input with the source shipped on the ISO.
  ankaLock =
    let
      upstream = lib.importJSON ../../flake.lock;
      rename   = name: if name == upstream.root then "anka" else name;
      fixInput = ref: if builtins.isList ref then [ "anka" ] ++ ref else rename ref;
      nodes = lib.mapAttrs' (name: node: lib.nameValuePair (rename name) (
        node // lib.optionalAttrs (node ? inputs) {
          inputs = lib.mapAttrs (_: fixInput) node.inputs;
        })) upstream.nodes;
    in
    if self ? rev then
      pkgs.writeText "flake.lock" (builtins.toJSON {
        inherit (upstream) version;
        root  = "root";
        nodes = nodes // {
          anka = nodes.anka // {
            locked   = flakeRepo // { inherit (self) rev narHash lastModified; };
            original = flakeRepo;
          };
          root.inputs.anka = "anka";
        };
      })
    else null;

  # Calamares .conf files are YAML; JSON is valid YAML.
  ankainstallConf = pkgs.writeText "ankainstall.conf" (builtins.toJSON {
    flakeUrl         = "github:${flakeRepo.owner}/${flakeRepo.repo}";
    ankaSource       = "${self}";
    lockFile         = if ankaLock == null then "" else "${ankaLock}";
    upstreamNixosJob = "${nixosExt}/lib/calamares/modules/nixos/main.py";
  });

  ankaCalamaresData = pkgs.runCommand "anka-calamares-data" { } ''
    mkdir -p $out/etc/calamares/modules $out/share/calamares/branding $out/lib/calamares/modules
    substitute ${./settings.conf} $out/etc/calamares/settings.conf \
      --replace-fail @ankaModules@ $out/lib/calamares/modules
    cp ${./modules}/*.conf $out/etc/calamares/modules/
    chmod u+w $out/etc/calamares/modules/*.conf
    substituteInPlace $out/etc/calamares/modules/packagechooser.conf \
      --replace-fail @ankaLogo@ ${../../modules/branding/artwork/logo.svg}
    cp ${ankainstallConf} $out/etc/calamares/modules/ankainstall.conf
    cp -r ${./branding/anka} $out/share/calamares/branding/anka
    chmod -R u+w $out/share/calamares/branding/anka
    cp ${../../modules/branding/artwork/logo.svg} $out/share/calamares/branding/anka/logo.svg
    install -Dm644 ${./ankainstall/module.desc} $out/lib/calamares/modules/ankainstall/module.desc
    install -Dm644 ${./ankainstall/main.py}     $out/lib/calamares/modules/ankainstall/main.py
  '';

  ankaCalamares = pkgs.calamares.override {
    extraWrapperArgs = [
      "--prefix XDG_DATA_DIRS : ${ankaCalamaresData}/share"
      # Searched in order: ANKA first, then the NixOS extension's defaults.
      "--prefix XDG_CONFIG_DIRS : ${nixosExt}/etc"
      "--prefix XDG_CONFIG_DIRS : ${ankaCalamaresData}/etc"
      "--add-flag --xdg-config"
    ];
  };

  # `pkexec calamares` wipes the environment, so the root Calamares cannot find
  # the live Plasma Wayland session and exits at once ("XDG_RUNTIME_DIR is
  # invalid", no Qt platform plugin). The live user has passwordless sudo
  # (iso/default.nix); keep the session variables across it.
  installAnka = pkgs.writeShellScriptBin "install-anka" ''
    exec /run/wrappers/bin/sudo \
      --preserve-env=WAYLAND_DISPLAY,XDG_RUNTIME_DIR,DISPLAY,XAUTHORITY,QT_QPA_PLATFORM,XDG_SESSION_TYPE \
      ${ankaCalamares}/bin/calamares "$@"
  '';

  # "Install ANKA" with the ANKA logo (desktop shortcut, app menu, autostart)
  # in place of Calamares' own "Install System" entry.
  installerDesktop = pkgs.writeTextDir "share/applications/calamares.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=Install ANKA
    Name[tr]=ANKA'yı Kur
    Comment=Install ANKA OS on this computer
    Comment[tr]=ANKA OS'i bu bilgisayara kur
    Exec=${installAnka}/bin/install-anka
    Icon=anka
    Terminal=false
    StartupNotify=true
    Categories=Qt;System;
    X-AppStream-Ignore=true
  '';
in
{
  # Calamares runs as root through `install-anka`; partitioning helpers
  # (kpmcore) may still call pkexec.
  security.polkit.enablePkexecWrapper = true;

  # kpmcore (Calamares' partitioning backend) needs it.
  programs.partition-manager.enable = true;

  # Every language the locale page offers.
  i18n.supportedLocales = [ "all" ];

  environment.systemPackages = [
    ankaCalamares
    installAnka
    (lib.hiPrio installerDesktop)
    # Open the installer as soon as the live desktop starts.
    (pkgs.makeAutostartItem { name = "calamares"; package = installerDesktop; })
    pkgs.glibcLocales
    pkgs.pciutils   # lspci, for GPU detection in ankainstall
  ];

}
