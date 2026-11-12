# CritMatic Forever

WoW Forever için kişisel rekor eklentisi. Her büyü için en yüksek kritik, en yüksek normal vuruş ve en yüksek dövüş toplamını hatırlar. Yeni rekoru ekranda, sohbette ve büyü ipucunda gösterir.

Bu, Classic Era'daki CritMatic eklentisinin kopyası değildir. Aynı işi Forever istemcisinde yapmak için sıfırdan yazıldı. Özgün CritMatic'in yazarıyla bağlantısı yoktur ve Blizzard'ın resmi eklentisi değildir.

## Forever'da ne çalışır

WoW Forever, Midnight ile aynı arayüz ailesindedir. Eklentiler savaş günlüğünü (`COMBAT_LOG_EVENT_UNFILTERED`) okuyamaz. Tek vuruşun sayısı ve kritik olup olmadığı dövüş sırasında gizli kalır. Bu yüzden kritik rekoru, istemci o günlüğü açmadığı sürece dolmaz. Dinleyici varsayılan olarak kapalıdır; açmak korumalı eylem hatası çıkarabilir.

Dövüş bitince oyunun kendi hasar ölçeri büyü toplamlarını verir. Eklenti bu toplamları **dövüş rekoru** olarak saklar. Bu, bir büyünün o dövüşte yaptığı toplam hasar ya da iyileştirmedir. Tek bir kritik değildir. Arayüzde bu ayrım yazılıdır.

Kritik ve normal vuruş kaydı kodda durur. İstemci savaş günlüğünü tekrar açarsa, Durum sekmesindeki anahtar ile dinleyici denenir ve rekorlar aynı kurallarla dolar.

## Kurulum

1. `CritMaticForever` klasörünü Forever eklenti dizinine kopyala:

   `World of Warcraft\_forever_\Interface\AddOns\CritMaticForever`

2. Klasörün içinde `CritMaticForever.toc` olmalı. Oyunu tamamen kapatıp aç. Yeni dosyalar `/reload` ile gelmez.
3. Karakter seçiminde eklenti listesinden **CritMatic Forever** kutusunu işaretle.

## Kullanım

| Komut | Ne yapar |
| --- | --- |
| `/cmf` veya `/cm` | Ayarlar |
| `/cmlog` | Kayıt penceresi |
| `/cmchangelog` | Yenilikler |
| `/cmf ignore Büyü Adı` | Büyüyü yok say |
| `/cmf ignoretarget İsim` | Hedefi yok say |
| `/cmf status` | Dinleyici ve kayıt sayısı |
| `/cmf demo` | Uyarı önizlemesi |
| `/cmreset` | Bu karakterin kayıtlarını sil |

Minimap düğmesi: sol tık kayıtlar, sağ tık ayarlar, sürükleyerek taşınır.

Kayıt penceresinde bir satıra sağ tıklayınca o rekor söyle, bağır, grup, raid, lonca veya fısıltı ile paylaşılır. Örneklemeyi oyun, örnek dışında bir donanım olayına (tıklama) bağlar; otomatik emot yok.

Büyü kitapçığında, aksiyon çubuğunda ve sohbet bağlantılarında ipucu, o büyünün rekorunu ekler.

## Ayarlar

Genel sekmesinde hasar, iyileştirme, kritik, normal vuruş, pet ve dövüş toplamı ayrı ayrı kapanır. Küçük vuruşlar için bir alt sınır yazılır. Uyarılar hemen ya da dövüş bitince gösterilir. Ses, yazı boyutu ve renkler değişir. Sohbet satırı ile dövüş sonu özeti ayrıdır.

## Geliştirme

Kayıt kuralları `CritMaticForever/Logic.lua` içindedir ve WoW API'si çağırmaz.

```bash
lua5.1 tests/logic_test.lua
lua5.1 tests/syntax.lua
```

CurseForge'a yüklerken arayüz `16001`, oyun sürümü `1.60.1`, flavor Forever (`gameVersionTypeId` 88568) seçilmeli. Paket, `CritMaticForever` klasörünü içermelidir.

## English

CritMatic Forever remembers, per spell, your highest crit, highest normal hit, and highest fight total. WoW Forever hides the combat log from addons, so crit records stay empty unless the client allows that event. The listener is off by default. After combat, spell totals from the built-in damage meter are stored as a fight best. That number is the whole fight, not one crit.

Copy `CritMaticForever` into `_forever_\Interface\AddOns\` and restart the client. `/cmf` opens settings. `/cmlog` opens the record window.
