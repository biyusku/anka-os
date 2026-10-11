"""Unit tests for the pure helpers of the ankainstall Calamares job.

Run: python3 -m unittest discover -s iso/calamares/tests
"""

import importlib.util
import io
import pathlib
import shutil
import sys
import tempfile
import types
import unittest
from unittest import mock

# The job imports `libcalamares`, which only exists inside Calamares.
sys.modules.setdefault("libcalamares", types.ModuleType("libcalamares"))

_MAIN = pathlib.Path(__file__).resolve().parent.parent / "ankainstall" / "main.py"
_spec = importlib.util.spec_from_file_location("ankainstall", _MAIN)
ankainstall = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ankainstall)

# `lspci -nn` lines from real machines.
AMD_RX6600 = "03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600/6600 XT/6600M] [1002:73ff] (rev c7)"
AMD_RAPHAEL_IGPU = "13:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Raphael [1002:164e] (rev c1)"
NVIDIA_RTX3060 = "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA106 [GeForce RTX 3060 Lite Hash Rate] [10de:2504] (rev a1)"
NVIDIA_GTX1060 = "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] [10de:1c03] (rev a1)"
NVIDIA_GTX1650_MOBILE = "01:00.0 3D controller [0302]: NVIDIA Corporation TU117M [GeForce GTX 1650 Mobile / Max-Q] [10de:1f99] (rev a1)"
INTEL_UHD = "00:02.0 VGA compatible controller [0300]: Intel Corporation CometLake-H GT2 [UHD Graphics] [8086:9bc4] (rev 05)"
QEMU_VIRTIO = "00:01.0 VGA compatible controller [0300]: Red Hat, Inc. Virtio 1.0 GPU [1af4:1050] (rev 01)"
NOT_A_GPU = "00:1f.3 Audio device [0403]: Intel Corporation Comet Lake PCH cAVS [8086:06c8]"


def lspci(*lines):
    return "\n".join(lines + (NOT_A_GPU,)) + "\n"


class DetectGpu(unittest.TestCase):
    def test_amd_desktop(self):
        self.assertEqual(ankainstall.detect_gpu(lspci(AMD_RX6600)), {"type": "amd"})

    def test_nvidia_card_wins_over_ryzen_igpu(self):
        self.assertEqual(
            ankainstall.detect_gpu(lspci(NVIDIA_RTX3060, AMD_RAPHAEL_IGPU)),
            {"type": "nvidia", "open": True},
        )

    def test_pre_turing_nvidia_uses_closed_modules(self):
        self.assertEqual(ankainstall.detect_gpu(lspci(NVIDIA_GTX1060)), {"type": "nvidia", "open": False})

    def test_intel_nvidia_laptop_gets_prime_bus_ids(self):
        self.assertEqual(
            ankainstall.detect_gpu(lspci(INTEL_UHD, NVIDIA_GTX1650_MOBILE)),
            {"type": "intel+nvidia", "open": True, "intelBusId": "PCI:0:2:0", "nvidiaBusId": "PCI:1:0:0"},
        )

    def test_bus_ids_are_decimal(self):
        gpu = ankainstall.detect_gpu(lspci(INTEL_UHD, NVIDIA_GTX1650_MOBILE.replace("01:00.0", "0000:c1:00.0")))
        self.assertEqual(gpu["nvidiaBusId"], "PCI:193:0:0")

    def test_intel_only(self):
        self.assertEqual(ankainstall.detect_gpu(lspci(INTEL_UHD)), {"type": "intel"})

    def test_virtual_machine(self):
        self.assertEqual(ankainstall.detect_gpu(lspci(QEMU_VIRTIO)), {"type": "none"})
        self.assertEqual(ankainstall.detect_gpu(""), {"type": "none"})


HARDWARE_CONFIG = """\
  fileSystems."/" =
    { device = "/dev/disk/by-uuid/1111";
      fsType = "btrfs";
      options = [ "subvol=/" ];
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/1111";
      fsType = "btrfs";
      options = [ "subvol=home" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/ABCD";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
"""


class FixBtrfsSubvolumes(unittest.TestCase):
    def test_rewrites_subvol_options(self):
        fixed = ankainstall.fix_btrfs_subvolumes(HARDWARE_CONFIG, [{"mountPoint": "/", "fs": "btrfs"}])
        self.assertIn('options = [ "subvol=@" ];', fixed)
        self.assertIn('options = [ "subvol=@home" ];', fixed)
        self.assertIn('options = [ "fmask=0077" "dmask=0077" ];', fixed)

    def test_leaves_non_btrfs_alone(self):
        self.assertEqual(
            ankainstall.fix_btrfs_subvolumes(HARDWARE_CONFIG, [{"mountPoint": "/", "fs": "ext4"}]),
            HARDWARE_CONFIG,
        )


KBD_MODEL_MAP = """\
# Generated from system-config-keyboard's model list
# consolelayout\t\txlayout\txmodel\t\txvariant\txoptions
us\t\t\tus\tpc105+inet\t-\t\tterminate:ctrl_alt_bksp
trq\t\t\ttr\tpc105\t\t-\t\tterminate:ctrl_alt_bksp
trf\t\t\ttr\tpc105\t\tf\t\tterminate:ctrl_alt_bksp
de-latin1-nodeadkeys\tde\tpc105\t\tnodeadkeys\tterminate:ctrl_alt_bksp
"""


class BtrfsMountPoints(unittest.TestCase):
    def test_btrfs_root_gets_all_subvolumes(self):
        parts = [{"mountPoint": "/", "fs": "btrfs"}, {"mountPoint": "/boot", "fs": "fat32"}]
        self.assertEqual(ankainstall.btrfs_mount_points(parts), ["/", "/home", "/nix", "/.snapshots"])

    def test_separate_ext4_home_is_skipped(self):
        parts = [{"mountPoint": "/", "fs": "btrfs"}, {"mountPoint": "/home", "fs": "ext4"}]
        self.assertEqual(ankainstall.btrfs_mount_points(parts), ["/", "/nix", "/.snapshots"])

    def test_ext4_root(self):
        self.assertEqual(ankainstall.btrfs_mount_points([{"mountPoint": "/", "fs": "ext4"}]), [])


class VconsoleKeymap(unittest.TestCase):
    def test_turkish_q(self):
        self.assertEqual(ankainstall.vconsole_keymap("tr", "", KBD_MODEL_MAP), "trq")

    def test_turkish_f(self):
        self.assertEqual(ankainstall.vconsole_keymap("tr", "f", KBD_MODEL_MAP), "trf")

    def test_unknown_layout(self):
        self.assertIsNone(ankainstall.vconsole_keymap("xx", "", KBD_MODEL_MAP))


def settings(**overrides):
    base = {
        "firmware": "efi",
        "boot_device": None,
        "root_fs": "btrfs",
        "root_luks": False,
        "btrfs_mounts": ["/", "/home", "/nix", "/.snapshots"],
        "gpu": {"type": "amd"},
        "hostname": "anka-ayse",
        "timezone": "Europe/Istanbul",
        "locale": "tr_TR.UTF-8",
        "locale_extra": {"LC_TIME": "en_GB.UTF-8"},
        "kb_layout": "tr",
        "kb_variant": "",
        "vconsole": "trq",
        "username": "ayse",
        "fullname": "Ayşe \"Dev\" Yılmaz",
        "autologin": False,
        "state_version": "26.11",
    }
    base.update(overrides)
    return base


class BuildConfiguration(unittest.TestCase):
    def test_efi_btrfs_desktop(self):
        cfg = ankainstall.build_configuration(settings())
        self.assertIn('anka.profile = "full";', cfg)
        self.assertIn('anka.boot.loader = "systemd-boot";', cfg)
        self.assertNotIn("grubDevice", cfg)
        self.assertIn('anka.filesystem.rootFormat = "btrfs";', cfg)
        self.assertIn("anka.filesystem.btrfsSubvolumes = true;", cfg)
        self.assertIn('fileSystems."/home".options = [ "compress=zstd:1" "noatime" ];', cfg)
        self.assertIn('anka.gpu.type = "amd";', cfg)
        self.assertIn('anka.network.hostname = "anka-ayse";', cfg)
        self.assertIn('time.timeZone = "Europe/Istanbul";', cfg)
        self.assertIn('i18n.defaultLocale = "tr_TR.UTF-8";', cfg)
        self.assertIn('LC_TIME = "en_GB.UTF-8";', cfg)
        self.assertIn('LC_MONETARY = "tr_TR.UTF-8";', cfg)
        self.assertIn('console.keyMap = "trq";', cfg)
        self.assertIn('users.users."ayse" = {', cfg)
        self.assertIn('description  = "Ayşe \\"Dev\\" Yılmaz";', cfg)
        self.assertNotIn("autoLogin", cfg)
        self.assertIn('system.stateVersion = "26.11";', cfg)

    def test_bios_ext4_luks_nvidia_laptop(self):
        cfg = ankainstall.build_configuration(settings(
            firmware="bios", boot_device="/dev/sda", root_fs="ext4", root_luks=True, btrfs_mounts=[],
            gpu={"type": "intel+nvidia", "open": True, "intelBusId": "PCI:0:2:0", "nvidiaBusId": "PCI:1:0:0"},
            autologin=True, profile="light",
        ))
        self.assertIn('anka.profile = "light";', cfg)
        self.assertIn('anka.boot.loader = "grub";', cfg)
        self.assertIn('anka.boot.grubDevice = "/dev/sda";', cfg)
        self.assertIn("boot.loader.grub.enableCryptodisk = true;", cfg)
        self.assertIn("anka.filesystem.btrfsSubvolumes = false;", cfg)
        self.assertNotIn("fileSystems.", cfg)
        self.assertIn("anka.gpu.nvidia.open = true;", cfg)
        self.assertIn('nvidiaBusId = "PCI:1:0:0";', cfg)
        self.assertIn('user   = "ayse";', cfg)

    def test_nix_interpolation_is_escaped(self):
        cfg = ankainstall.build_configuration(settings(fullname="${builtins.abort 1}"))
        self.assertIn('description  = "\\${builtins.abort 1}";', cfg)

    def test_braces_are_balanced(self):
        for s in (settings(), settings(firmware="bios", autologin=True, gpu={"type": "intel+nvidia", "open": False,
                                                                           "intelBusId": "PCI:0:2:0",
                                                                           "nvidiaBusId": "PCI:1:0:0"})):
            cfg = ankainstall.build_configuration(s)
            self.assertEqual(cfg.count("{"), cfg.count("}"), cfg)


class BuildFlake(unittest.TestCase):
    def test_uses_anka_input(self):
        flake = ankainstall.build_flake("github:biyusku/anka-os")
        self.assertIn('inputs.anka.url = "github:biyusku/anka-os";', flake)
        self.assertIn("nixosConfigurations.anka = anka.lib.mkSystem {", flake)


FAKE_UPSTREAM_JOB = """
def generateProxyStrings():
    return []

class NixProgress:
    def __init__(self):
        self.fraction = 0.0
        self.log_messages = []

    def handle(self, line):
        return line.startswith("@nix ")
"""


class FakeGlobalStorage:
    def __init__(self, values):
        self.values = values

    def value(self, key):
        return self.values.get(key)


class Run(unittest.TestCase):
    """Drive run() with a fake Calamares and fake system commands."""

    def setUp(self):
        tmp = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        self.root = tmp / "mnt"
        (self.root / "etc/nixos").mkdir(parents=True)
        upstream = tmp / "upstream.py"
        upstream.write_text(FAKE_UPSTREAM_JOB)
        lock = tmp / "flake.lock"
        lock.write_text('{"version": 7}')

        self.commands = commands = []

        def check_output(cmd, **kwargs):
            commands.append(cmd)
            if "nixos-generate-config" in cmd:
                (self.root / "etc/nixos/hardware-configuration.nix").write_text(HARDWARE_CONFIG)
            if cmd[0] == "lspci":
                return (NVIDIA_RTX3060 + "\n").encode()
            return b""

        class FakePopen:
            def __init__(self, cmd, **kwargs):
                commands.append(cmd)
                self.stdout = io.BytesIO(b'@nix {"action":"msg"}\ninstalling the boot loader\n')

            def wait(self):
                return 0

        def host_env_process_output(cmd, _cb, stdin):
            pathlib.Path(cmd[2]).write_text(stdin)

        calamares = types.SimpleNamespace(
            globalstorage=FakeGlobalStorage({
                "rootMountPoint": str(self.root),
                "firmwareType": "efi",
                "partitions": [{"mountPoint": "/", "fs": "btrfs", "fsName": "btrfs"}],
                "hostname": "anka-ayse",
                "locationRegion": "Europe", "locationZone": "Istanbul",
                "localeConf": {"LANG": "tr_TR.UTF-8/UTF-8", "LC_TIME": "tr_TR.UTF-8/UTF-8"},
                "keyboardLayout": "us", "keyboardVariant": "",
                "username": "ayse", "fullname": "Ayse",
                "packagechooser_packagechooser": "light",
            }),
            job=types.SimpleNamespace(
                configuration={
                    "flakeUrl": "github:biyusku/anka-os",
                    "ankaSource": "/nix/store/xxx-source",
                    "lockFile": str(lock),
                    "upstreamNixosJob": str(upstream),
                },
                setprogress=lambda _p: None,
            ),
            utils=types.SimpleNamespace(
                host_env_process_output=host_env_process_output,
                debug=lambda _m: None, warning=lambda _m: None,
            ),
        )
        for patch in (
            mock.patch.object(ankainstall, "libcalamares", calamares),
            mock.patch.object(ankainstall.subprocess, "check_output", check_output),
            mock.patch.object(ankainstall.subprocess, "getoutput", lambda _c: "26.11.20261003.a7868a7 (Yarara)"),
            mock.patch.object(ankainstall.subprocess, "Popen", FakePopen),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def test_writes_flake_and_installs(self):
        self.assertIsNone(ankainstall.run())
        etc = self.root / "etc/nixos"
        self.assertIn("anka.lib.mkSystem", (etc / "flake.nix").read_text())
        self.assertEqual((etc / "flake.lock").read_text(), '{"version": 7}')
        config = (etc / "configuration.nix").read_text()
        self.assertIn('anka.gpu.type = "nvidia";', config)
        self.assertIn('anka.profile = "light";', config)
        self.assertIn('time.timeZone = "Europe/Istanbul";', config)
        self.assertIn('system.stateVersion = "26.11";', config)
        self.assertIn('"subvol=@home"', (etc / "hardware-configuration.nix").read_text())
        install = self.commands[-1]
        self.assertEqual(install[:2], ["pkexec", "nixos-install"])
        self.assertIn(str(etc) + "#anka", install)
        self.assertNotIn("--override-input", install)


if __name__ == "__main__":
    unittest.main()
