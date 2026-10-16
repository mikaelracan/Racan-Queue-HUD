# Racan Queue HUD 0.4.1 — WoW Retail 12.1.5

**Jeden addon se dvěma automaticky přepínanými režimy.** Všechny schválené funkce původních verzí zůstávají zachované. **Jediná změna vzhledu:** místo původních role ikon Blizzardu jsou nyní výchozí minimalistické modré/zelené/žluté obrysové ikony (štít/kříž/meče). Anglické popisky, nulové pozadí, žádný nadpis FRONTA a přesun přes `/rqh unlock` a `/rqh lock` se nemění. Není napojen na Blizzard Edit Mode.

## Ikony – NOVÉ ve verzi 0.4.1

- **Výchozí styl „modern“:** obrysový štít pro tanka (modrá `#3FA9FF`), zdravotnický kříž pro healera (zelená `#31E85F`) a zkřížené meče pro DPS (žlutá `#FFD43B`). Jde o tvary z ikon Lucide 0.456.0, uložené jako vlastní průhledné PNG 128 × 128. Hra je barví pomocí SetVertexColor. Žádný obdélník nebo pozadí.
- Tyto ikony se používají **v obou režimech: queue i raid**, aby vzhled působil jednotně. Při nedostatečném obsazení se ikona mírně ztmaví, jako u původní 0.4.0.
- **`/rqh icons blizzard`** – kdykoli přepneš na původní role ikony Blizzardu.
- **`/rqh icons modern`** – vrátí nové obrysové ikony.
- Výběr stylu se ukládá do SavedVariables a zachová se po `/reload`.

## Režimy

| Herní stav | Tank | Healer | DPS | Význam |
| --- | --- | --- | --- | --- |
| LFD/LFR fronta | `0/1` | `0/1` | `3/3` | **nalezeno / požadováno**, stejně jako 0.3.1, včetně časů |
| Uvnitř **LFR raidu** | `2/1/0` | `3/3/2` | `20/20/15` | **požadováno / přítomno / naživu** |
| Uvnitř **ručně sestaveného raidu** (Normal/Heroic/Mythic) | `1/0` | `3/2` | `20/15` | **přítomno / naživu**, bez prvního čísla |

Hodnoty výše jsou ILUSTRAČNÍ. Realita se získává z konkrétního LFR křídla a živého raid rosteru. U ručně sestaveného raidu se role počítají z uživatelem/raidem nastavených combat rolí; addon neodhaduje roli podle classy, stromu talentů nebo počtu lidí.

**Automatické přepínání:** při přihlášení do fronty zobrazí původní Queue HUD; při vstupu do raid instance a s členstvím v raidu zobrazí Raid HUD místo fronty. Po opuštění raid instance se vrátí k frontě, pokud nějaká zůstala, jinak se skryje. Nevytváří dvě okna, nepřepíná pozici a nemění stav fronty.

## Význam barev v raid režimu

- Tank = modrá `#3FA9FF`, healer = zelená `#31E85F`, DPS = žlutá `#FFD43B`.
- **LFR:** První číslo (požadováno) je v barvě role. Druhé se zbarví, když je role plně obsazena. Třetí je v barvě role, pokud jsou všichni přítomní naživu, a červené, pokud část hráčů zemřela nebo není online.
- **Ručně sestavený raid:** První číslo (přítomno) je v barvě role. Druhé je barevné, když všichni přítomní žijí, jinak červené.
- Oddělovače `/` si zachovávají původní barvu. Ve frontě se barevná pravidla 0.3.1 vůbec nemění.

## Co znamená „přítomno“ a „naživu“

- **Přítomno:** hráči, kteří jsou stále na seznamu raidu, ať jsou online či offline. Po opuštění raidu zmizí z druhého počtu.
- **Naživu:** online členové raidu, u nichž hra potvrzuje živý stav. Mrtví/duchové se nepočítají. Po resurrectu se hodnota opět zvedne. Offline hráč je dál v raid rosteru, ale není považován za online/živého; poznámka jej označí jako `Offline (not alive)`.
- **Nepřiřazené role:** člen, kterému raid/uživatel nevybral TANK, HEALER ani DAMAGER, není automaticky DPS. Bude uveden v doplňkové poznámce `Unassigned roles: N` a nebude neprávem přičten k žádné roli. To je důležité především pro premade raidy.
- **Nedostupná/secret data:** Pokud údaje o živých nelze legálně zjistit, příslušný počet bude `?` místo vymyšlené hodnoty; poznámka `Unknown alive status: N` upozorní na příčinu.

## Jak získáváme požadovaný počet v LFR

LFR role requirements bereme z `GetLFGQueueStats` **konkrétního LFR křídla, když ještě čekáš na vstup**; uloží se do databáze pod identifikátorem křídla. Při přechodu do raidu použijeme pouze odpovídající identifikátor z `GetInstanceInfo`. Pokud jej klient po vstupu nevrací, může addon použít jediný dostupný nedávný záznam; u více současných LFR front raději napíše `?`. Data mají ochranu proti zastarání (4 hodiny). Není zde natvrdo nastaveno 2/3/20 ani jiné složení. Pokud ses do raidu připojil před aktivací addonu nebo klient požadované počty nedává, první číslo může být `?`.

## Instalace / upgrade

1. Ukonči WoW.
2. Rozbal ZIP. Složka musí být přesně `_retail_/Interface/AddOns/RacanQueueHUD/` a přímo v ní musí být `RacanQueueHUD.toc`.
3. Nahraď soubory dosavadní verze (0.4.0 či starší) soubory 0.4.1. **Název složky ani databáze se nemění**, takže nastavená poloha, měřítko a zamčení zůstávají zachované.
4. Spusť WoW Retail. Doporučuji zapnout zobrazení Lua chyb přes `/console scriptErrors 1`.

## Příkazy

| Příkaz | Funkce |
| --- | --- |
| `/rqh unlock` | Modrý obrys pro přesun myší; pozice je uložena |
| `/rqh lock` | Zamknout, bez rámečku a bez klikatelného pozadí |
| `/rqh test` nebo `/rqh test queue` | Ukázka původní fronty mimo skutečnou frontu/raid |
| `/rqh test lfr` | Ukázka LFR raidu `2/1/0`, `3/3/2`, `20/20/15` |
| `/rqh test manual` | Ukázka ručně sestaveného raidu `1/0`, `3/2`, `20/15` |
| `/rqh icons modern` | Nové minimalistické barevné ikony (výchozí) |
| `/rqh icons blizzard` | Vrátit původní ikony Blizzardu |
| `/rqh scale 1.2` | Velikost, rozsah 0.6–2.0 |
| `/rqh on` / `/rqh off` | Zapnutí/vypnutí HUD; nikdy neovlivní skutečnou frontu |
| `/rqh reset` | Výchozí nastavení a vymazání předchozího cache požadavků rolí |
| `/rqh debug` | Výpis typu raidu, aktuálního rosteru, rolí, dostupnosti API a případných problémů |

Příkazy `/rqh test ...` nezaměňují ilustrační čísla za živá herní data, pokud jsi zrovna přihlášený do fronty nebo uvnitř raidu. V tu chvíli má prioritu skutečný stav.

## Ověření

Balíček obsahuje testy v `Tests/test_queue.lua`. Jsou **offline mock testy** provedené v Lua 5.3, které prověřují Queue HUD, raid režimy, změny rosteru, smrti, resurrecty, LFR cílové počty, nedostupné/secret hodnoty, přesun a přepínání. Nejde o plný simulátor WoW ani o ověření skutečné Midnight secure execution. Konečné potvrzení vyžaduje zkoušku v klientu, zejména po přijetí LFR a při živém bossovi.

Verze: **0.4.1**, Retail **12.1.5**, Interface **120105**.

Moderní ikony: Media/Icons/tank.png, healer.png, dps.png. Originální SVG pro rekonstrukci jsou přiložena. Licence: Media/Icons/LICENSE-LUCIDE.txt.
