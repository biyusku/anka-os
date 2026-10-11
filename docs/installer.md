# ANKA OS — Kurulum Programı

Live ISO açıldığında ANKA kurulum programı (Calamares) kendiliğinden başlar.
Masaüstündeki **Install ANKA OS** kısayolu da aynı programı açar.

## Kullanıcının gördüğü adımlar

1. **Hoş geldin:** disk (20 GB), RAM (2 GB) ve internet bağlantısı kontrol edilir.
   ANKA ve paketleri kurulum sırasında indirildiği için internet gereklidir.
2. **Konum / dil:** saat dilimi ve dil seçilir.
3. **Klavye**
4. **Kullanıcı:** ad, kullanıcı adı ve parola girilir. Yönetici (root) hesabı
   varsayılan olarak aynı parolayı kullanır.
5. **Disk:** varsayılan dosya sistemi Btrfs'tir (`@`, `@home`, `@nix`,
   `@snapshots` alt hacimleri ve snapper anlık görüntüleri). ext4 ve LUKS
   şifreleme de seçilebilir. Swap bölümü oluşturulmaz, zram kullanılır.
6. **Özet** → kurulum → **Bitti**

## Arka planda olanlar

`ankainstall` adımı (`iso/calamares/ankainstall/main.py`) şunları yapar:

1. `nixos-generate-config` ile `hardware-configuration.nix` üretir ve btrfs
   alt hacim seçeneklerini `mount.conf` düzeniyle eşitler.
2. Ekran kartını `lspci` ile algılar:

   | Donanım | `anka.gpu.type` |
   |---|---|
   | NVIDIA (tek başına veya AMD iGPU ile) | `nvidia` (Turing+ için open modüller) |
   | Intel + NVIDIA dizüstü | `intel+nvidia` (PRIME offload, bus ID'leri otomatik) |
   | AMD | `amd` |
   | Intel | `intel` |
   | Sanal makine / bilinmeyen | `none` |

3. `/etc/nixos` klasörünü ANKA'yı girdi olarak kullanan küçük bir flake olarak yazar:

   ```
   /etc/nixos/flake.nix                  inputs.anka.url = "github:biyusku/anka-os"
   /etc/nixos/flake.lock                 ANKA, ISO'nun derlendiği commit'e sabitlenir
   /etc/nixos/hardware-configuration.nix
   /etc/nixos/configuration.nix          kurulumda yapılan seçimler
   ```

4. `nixos-install --flake /etc/nixos#anka` çalıştırır.
5. Calamares'in `users` adımı kullanıcının parolasını ayarlar. Kullanıcının
   kendisi `configuration.nix` içinde tanımlıdır.

ANKA'nın varsayılanları (`profiles/default.nix`) `lib.mkDefault` ile
verilir. Bu yüzden `configuration.nix` içine yazılan her ayar bunları
çakışma olmadan geçersiz kılar.

## Kurulumdan sonra

```bash
# Ayar değiştir (configuration.nix'i düzenledikten sonra)
sudo nixos-rebuild switch --flake /etc/nixos#anka

# ANKA'yı güncelle
sudo nix flake update anka --flake /etc/nixos
sudo nixos-rebuild switch --flake /etc/nixos#anka
```

## Geliştirme

- Calamares ayarları: `iso/calamares/` (`settings.conf`, `modules/*.conf`,
  `branding/anka/`)
- Paketleme: `iso/calamares/default.nix`. nixpkgs'teki `calamares-nixos`
  her zaman kendi (düz NixOS) ayarlarını önce okuduğu için ANKA kendi
  sarmalanmış Calamares'ini kullanır.
- Testler: `python3 -m unittest discover -s iso/calamares/tests`
- ISO'yu test et: `make build-iso && make test-iso-uefi`
