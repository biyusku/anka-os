# ANKA OS — Branding Kılavuzu

## İsim
**ANKA** — Türk mitolojisinde Zümrüdüanka (anka kuşu), ateşten doğan ve külden yenilenen phoenix.

## Vizyon Cümlesi
"Eski bir laptop, yeni bir hayat."

## Neden ANKA?
- Türk kökenli, dünya genelinde söylenebilir (AN-ka)
- Phoenix metaforu: eski/zayıf donanımı yeniden doğuran OS
- 2 hece, temiz, kurumsal
- OS dünyasında kullanılmamış, trademark riski düşük
- Logo için zengin: soyut anka/phoenix figürü

## Logo Yönü
- Soyut, minimalist anka figürü
- Ateş → dijital dönüşüm metaforu
- Renk paleti: derin kırmızı + altın sarısı (anka tüyü renkleri)

## Tagline Adayları
- "Rise with ANKA"
- "Your machine, reborn."
- "Every child deserves this."

## Teknik İsimler
- OS adı: ANKA
- D-Bus servis: org.anka.AI
- Systemd servisleri: anka-ai.service, anka-update.service
- MCP sunucuları: anka-mcp-filesystem, anka-mcp-desktop vb.
- Kullanıcı grubu: anka-users
- Config dizini: ~/.config/anka/

## Görünüm (uygulanan)

Hedef: Mac kadar sade. Her ekranda tek bir fikir, az kelime, tek bir ana düğme.

| Yer | Görünüm | Kaynak |
|---|---|---|
| Açılış menüsü | Gizli; açılırken **Boşluk** (GRUB'da Shift/Esc) basılı tutulunca görünür. Windows varsa 5 sn görünür. Canlı USB'de: siyah zemin, logo, kısa liste | `modules/system/boot.nix`, `modules/branding/grub/` |
| Açılış ekranı | Siyah zemin, ortada logo, altında ince ilerleme çubuğu (Plymouth `anka`) | `modules/branding/plymouth/` |
| Giriş / kilit ekranı | ANKA duvar kâğıdı, Inter | `modules/branding/default.nix` |
| Masaüstü açılışı | Açılış ekranıyla aynı logo ve çubuk (ksplash) | `look-and-feel/contents/splash/` |
| Masaüstü | Üstte ince çubuk (ANKA menüsü · simgeler · saat), altta ortalanmış yüzen dock | `look-and-feel/contents/layouts/` |
| Pencereler | Düğmeler sadece sağda (küçült · büyüt · kapat) | `kwinrc` (default.nix) |
| Karşılama, AI yanıtı | Tek pencere; büyük simge, başlık, bir satır metin, vurgu renginde ana düğme | `pkgs/anka-ui/` |
| ANKA Updates | Sürüm, tek satır durum, tek ana düğme; günlük ve geri dönüş bir tık ötede | `modules/update/kcm/ui/main.qml` |
| Kurulum | Sade kenar çubuğu, kısa slaytlar (seçilen dilde) | `iso/calamares/branding/anka/` |

**Renkler** (`modules/branding/colors.nix` → `ANKA.colors` + `/etc/xdg/kdeglobals`):
mavi tonsuz grafit griler (pencere `#1e1e1e`, metin `#f5f5f7`, ikincil metin
`#98989d`), vurgu `#c0392b` (ANKA kırmızısı), odak `#e74c3c`, bağlantı `#f39c12` (altın).

**Yazı tipi:** Inter (arayüz), eksik diller için Noto; sabit genişlik: sistemin
monospace'i.

**Simgeler:** `anka` (renkli logo), `anka-symbolic` (üst çubuk, metin renginde),
`anka-ai` (asistan). Kaynaklar `modules/branding/artwork/`.
