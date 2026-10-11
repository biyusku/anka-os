# ANKA OS — AI assistant
#
# Ollama runs the local model; the anka-ai daemon (org.anka.AI on the
# session bus) answers questions with it. `anka-ai "question"` asks from a
# terminal. The model is downloaded the first time someone asks, not at boot.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.anka.ai;

  anka-ai-pkg = pkgs.python3Packages.buildPythonApplication {
    pname   = "anka-ai";
    version = "0.3.0";
    pyproject = true;

    src = ../../services/anka-ai/anka-ai;

    build-system = with pkgs.python3Packages; [ hatchling ];

    nativeBuildInputs = with pkgs; [
      gobject-introspection
      wrapGAppsNoGuiHook
    ];

    buildInputs = [ pkgs.glib ];

    dependencies = with pkgs.python3Packages; [
      dbus-python
      pygobject3
      requests
    ];

    # One wrapper for both: python + GI typelib paths.
    dontWrapGApps = true;
    preFixup = ''
      makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
    '';

    pythonImportsCheck = [ "daemon" "dbus_bridge" ];

    # KRunner (Alt+Space): "ai <question>" / "? <question>" — the daemon
    # implements org.kde.krunner1 on /krunner.
    postInstall = ''
      mkdir -p $out/share/krunner/dbusplugins
      cat > $out/share/krunner/dbusplugins/anka-ai.desktop <<'EOF'
      [Desktop Entry]
      Name=ANKA AI
      Comment=Ask the ANKA AI assistant: "ai <question>"
      Icon=anka
      Type=Service
      X-KDE-ServiceTypes=Plasma/Runner
      X-KDE-PluginInfo-Name=anka-ai
      X-KDE-PluginInfo-Author=ANKA OS
      X-KDE-PluginInfo-Version=1.0
      X-KDE-PluginInfo-License=MIT
      X-KDE-PluginInfo-EnabledByDefault=true
      X-Plasma-API=DBus
      X-Plasma-DBusRunner-Service=org.anka.AI
      X-Plasma-DBusRunner-Path=/krunner
      X-Plasma-Request-Actions-Once=true
      EOF
    '';

    meta = {
      description = "ANKA OS AI assistant daemon";
      license     = lib.licenses.mit;
      platforms   = lib.platforms.linux;
      mainProgram = "anka-ai";
    };
  };
in
{
  imports = [ ./mcp.nix ];

  options.anka.ai = {
    enable = mkEnableOption "ANKA AI Assistant";

    localModel = mkOption {
      type = types.str;
      default = "qwen2.5:7b";
      description = "Ollama model ANKA AI answers with (downloaded on first use).";
    };

    port = mkOption {
      type = types.int;
      default = 11434;
      description = "Ollama service port";
    };

    acceleration = mkOption {
      type = types.enum [ "auto" "cpu" "vulkan" "rocm" "cuda" ];
      default = "auto";
      description = ''
        How Ollama runs the model.
        auto   — Vulkan when ANKA drives a GPU (anka.gpu.type), CPU otherwise.
        vulkan — any AMD, NVIDIA or Intel GPU; prebuilt.
        rocm   — AMD ROCm; prebuilt but several GB larger.
        cuda   — NVIDIA CUDA; not in the binary cache, compiles on the machine.
      '';
    };

    enableVoice = mkOption {
      type = types.bool;
      default = false;
      description = "Reserved for voice input/output (Whisper STT + Kokoro TTS); not wired yet.";
    };

    whisperModel = mkOption {
      type = types.str;
      default = "base";
      description = "Reserved: Whisper model size (tiny, base, small, medium, large).";
    };
  };

  config = mkIf cfg.enable {
    services.ollama = {
      enable = true;
      port = cfg.port;
      package = {
        cpu    = pkgs.ollama;
        vulkan = pkgs.ollama-vulkan;
        rocm   = pkgs.ollama-rocm;
        cuda   = pkgs.ollama-cuda;
      }.${if cfg.acceleration == "auto"
          then (if config.anka.gpu.type == "none" then "cpu" else "vulkan")
          else cfg.acceleration};
    };

    # Started with the desktop session; logs go to the user journal
    # (journalctl --user -u anka-ai).
    systemd.user.services.anka-ai = {
      description = "ANKA AI Daemon (org.anka.AI)";
      after    = [ "graphical-session.target" "dbus.socket" ];
      requires = [ "dbus.socket" ];
      wantedBy = [ "graphical-session.target" ];

      environment = {
        ANKA_KDIALOG  = "${pkgs.kdePackages.kdialog}/bin/kdialog";   # KRunner answers
        ANKA_AI_MODEL = cfg.localModel;
        OLLAMA_HOST   = "http://localhost:${toString cfg.port}";
      };

      serviceConfig = {
        Type             = "dbus";
        BusName          = "org.anka.AI";
        ExecStart        = "${anka-ai-pkg}/bin/anka-ai-daemon";
        Restart          = "on-failure";
        RestartSec       = "5s";
        SyslogIdentifier = "anka-ai";
      };
    };

    environment.systemPackages = [ anka-ai-pkg ];

    # Built by `nix flake check` (see checks in flake.nix)
    system.build.ankaAi = anka-ai-pkg;
  };
}
