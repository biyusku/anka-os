{ lib, ... }:

# ANKA OS Version Information
# This file is auto-updated by the build system

{
  ankaVersion = {
    major = 0;
    minor = 1;
    patch = 0;
    codename = "Phoenix";
    full = "0.1.0-Phoenix";

    # Build metadata
    buildDate = "2025-01-01";
    nixosBase = "24.05";

    # Component versions
    components = {
      ankaAI = "0.1.0";
      ankaMCP = "0.1.0";
      ankaUpdate = "0.1.0";
    };
  };

  # Helper to format version string
  mkVersionString = v: "${toString v.major}.${toString v.minor}.${toString v.patch}";
}