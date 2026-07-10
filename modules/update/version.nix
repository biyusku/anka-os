{ lib, ... }:

# ANKA OS Version Information
# This file is auto-updated by the build system

{
  options.anka.version = {
    major = lib.mkOption {
      type        = lib.types.int;
      default     = 0;
      readOnly    = true;
      description = "ANKA OS major version number";
    };

    minor = lib.mkOption {
      type        = lib.types.int;
      default     = 1;
      readOnly    = true;
      description = "ANKA OS minor version number";
    };

    patch = lib.mkOption {
      type        = lib.types.int;
      default     = 0;
      readOnly    = true;
      description = "ANKA OS patch version number";
    };

    codename = lib.mkOption {
      type        = lib.types.str;
      default     = "Phoenix";
      readOnly    = true;
      description = "ANKA OS release codename";
    };

    full = lib.mkOption {
      type        = lib.types.str;
      default     = "0.1.0-Phoenix";
      readOnly    = true;
      description = "Full ANKA OS version string (major.minor.patch-codename)";
    };

    nixosBase = lib.mkOption {
      type        = lib.types.str;
      default     = "24.05";
      readOnly    = true;
      description = "NixOS base release this ANKA version is built on";
    };
  };
}