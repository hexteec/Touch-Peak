<p align="center">
  <img src="assets/icon.png" width="96" alt="Ikona Touch Peak">
</p>

<h1 align="center">Touch Peak</h1>

<p align="center">
  Sterowanie kamerą i zaznaczanie <b>dotykiem</b> w Roblox Studio — obracaj, przybliżaj
  i przesuwaj widok palcami, a obiekty zaznaczaj stuknięciem.
</p>

![Podgląd okna Touch Peak](assets/preview.png)

> Obrazki w tym README to rendery poglądowe wygenerowane narzędziem z `tools/preview`
> (ten sam kod UI, uruchomiony poza Studio). W Studio używana jest czcionka Builder Sans,
> a ikony gestów są animowane.

## Gesty

| Gest | Co robi |
| --- | --- |
| ☝️ **Jeden palec** – przesuwanie | Obraca kamerę wokół punktu na środku ekranu (orbita) albo w miejscu |
| 👆↕️ **Stuknij, potem przeciągnij** | Zoom jednym palcem: w górę przybliża, w dół oddala (jak w Mapach Google) |
| 🕹️ **Joystick** (lewy dolny róg) | Kamera leci w stronę wychylenia – im dalej, tym szybciej |
| 🎚️ **Suwak zoomu** (obok joysticka) | W górę – przybliża, w dół – oddala, płynnie dopóki trzymasz |
| 🤏 **Dwa palce** – rozsuwanie / zsuwanie | Przybliża / oddala w stronę punktu między palcami |
| ✌️ **Dwa palce** – w tę samą stronę | Przesuwa widok (pan) – świat „trzyma się” palców |
| 👆 **Stuknięcie** | Zaznacza obiekt (jak kliknięcie w Studio); stuknięcie w pustkę odznacza |
| 👆👆 **Podwójne stuknięcie** | Zaznacza obiekt i płynnie ustawia na nim kamerę |
| ✋ **Przytrzymanie** | Dodaje obiekt do zaznaczenia albo go z niego usuwa |

### Dlaczego jednym palcem?

Roblox Studio na Windows zwykle przekazuje pluginom ekran dotykowy **jako mysz**: widzi tylko
jeden palec, a drugi w ogóle do pluginu nie dociera (to ograniczenie Studio, nie da się go
obejść z poziomu pluginu). Dlatego wszystko da się zrobić jednym palcem, bez przełączania trybów:

- **obrót** – zwykłe przeciągnięcie,
- **zoom** – stuknij i od razu przeciągnij w górę/dół (przybliża w stronę miejsca, gdzie
  dotknąłeś; samo stuknięcie nie zmieni wtedy zaznaczenia) albo suwak,
- **przesuwanie** – joystick: pchnij i trzymaj, kamera leci w tę stronę.

Jeśli Twoje urządzenie jednak przekazuje dwa palce, gesty dwoma palcami działają dodatkowo,
a joystick można trzymać jedną ręką i jednocześnie obracać kamerę drugą.

Dodatkowo:

- **Bezwładność** – po szybkim machnięciu kamera chwilę jeszcze się przesuwa i płynnie wyhamowuje.
- **Przelatywanie przez ściany** – przy bardzo bliskim przybliżeniu kamera zaczyna lecieć
  do przodu, więc da się „wejść” do budynku.
- **Kółka pod palcami** – widać, gdzie Studio rejestruje dotyk, a dwa palce łączy linia.
- **Podpowiedzi** – nazwa aktualnego gestu na dole ekranu i krótkie komunikaty
  („Zaznaczono: Model”) na górze.

## Okno pluginu

Kliknij przycisk **Touch Peak** na karcie **Plugins** – otworzy się pływające okno nad
widokiem 3D, a sterowanie dotykiem od razu się włączy.

- **Nagłówek** pokazuje stan: zielona pulsująca kropka = *Aktywny* (z nazwą gestu w trakcie
  ruchu), żółta = *Wstrzymany*.
- **Przeciągnij nagłówek** (palcem albo myszą), aby przesunąć okno. Pozycja jest zapamiętywana.
- **Strzałka** zwija okno do małej pigułki ze statusem; stuknięcie pigułki rozwija je z powrotem.
- **×** zamyka okno i wyłącza sterowanie dotykiem (tak samo jak ponowne kliknięcie przycisku
  na pasku).
- Karta **Gesty** – animowana ściąga ze wszystkimi gestami.
- Karta **Ustawienia** – czułość i opcje (niżej).

| Ustawienia i diagnostyka | Zwinięte okno |
| --- | --- |
| ![Karta ustawień z diagnostyką](assets/preview-settings.png) | ![Zwinięte okno](assets/preview-collapsed.png) |

### Ustawienia

| Opcja | Opis |
| --- | --- |
| Czułość obrotu / przybliżania / przesuwania | Od 0.25× do 3× |
| Tryb obrotu | **Orbita** wokół punktu, na który patrzysz, albo **W miejscu** (jak prawy przycisk myszy w Studio) |
| Bezwładność | Płynne wyhamowanie po machnięciu |
| Zoom i pan razem | Domyślnie gest dwoma palcami „blokuje się” na zoomie albo przesuwaniu; po włączeniu działają oba naraz |
| Odwróć obrót / Odwróć przesuwanie | Zmienia kierunek, np. żeby kamera leciała w stronę ruchu palców |
| Zaznaczaj całe modele | Stuknięcie części modelu zaznacza cały model (jak w Studio); wyłączone – samą część |
| Pokazuj dotyk | Kółka pod palcami i fala po stuknięciu |
| Mysz i rysik | Lewy przycisk myszy / rysik działa jak jeden palec – **zostaw włączone**, jeśli Studio podaje dotyk jako mysz |
| Joystick i suwak zoomu | Pokazuje joystick i suwak w lewym dolnym rogu widoku |
| Język | Auto (polski, gdy Studio lub system jest po polsku), PL albo EN |

Wszystkie ustawienia zapisują się w Studio i przetrwają restart.

## Instalacja

### Sposób 1 – gotowy plik (najprościej)

1. Pobierz plik [`dist/TouchPeak.rbxmx`](dist/TouchPeak.rbxmx).
2. W Studio otwórz kartę **Plugins → Plugins Folder** i wrzuć tam plik
   (Windows: `%LOCALAPPDATA%\Roblox\Plugins`, macOS: `~/Documents/Roblox/Plugins`).
3. Uruchom Studio ponownie – na karcie **Plugins** pojawi się przycisk **Touch Peak**.

### Sposób 2 – Rojo

```bash
rojo build default.project.json --plugin TouchPeak.rbxmx
```

### Sposób 3 – skrypt Pythona (bez Rojo)

```bash
python tools/build_plugin.py --output "%LOCALAPPDATA%/Roblox/Plugins/TouchPeak.rbxmx"
```

### Ikona na pasku (opcjonalnie)

Przycisk działa bez ikony. Żeby ją dodać, wgraj [`assets/icon.png`](assets/icon.png) do Roblox
(Creator Hub → Decals), wklej `rbxassetid://<id>` do `ToolbarIcon` w
[`src/Config.luau`](src/Config.luau) i zbuduj plugin ponownie.

## Jak to działa i czego się spodziewać

- **Co Studio naprawdę przekazuje** widać w **Ustawienia → Diagnostyka** (liczniki na żywo):
  - **Dotyk – maks. palców: 2** (na zielono) → Studio podaje prawdziwy multi-touch, działają
    gesty dwoma palcami.
  - **Dotyk: 0 zdarzeń**, a rośnie **Mysz** → Studio zamienia dotyk na mysz (jeden palec).
    W statusie zamiast „Palce” pojawi się „Mysz”. Używaj stuknij-i-przeciągnij oraz joysticka.
  - **Gesty Studio – pinch** → jeśli Studio zgłasza własny gest szczypania, plugin używa go
    do zoomu, nawet gdy pojedyncze palce nie docierają.
- Gdy sterowanie jest aktywne, plugin przejmuje mysz w widoku 3D – jak każde narzędzie Studio.
  Dzięki temu narzędzia Select/Move nie reagują przy okazji na palce (nie przesuniesz
  przypadkiem części). Wybranie innego narzędzia Studio **wstrzymuje** Touch Peak – wróć
  przełącznikiem „Sterowanie dotykiem” w oknie.
- Windows dorabia do dotyku „sztuczne” kliknięcia myszą; Touch Peak ignoruje mysz przez
  chwilę po każdym dotyku, więc nic nie dzieje się podwójnie.
- Zaznaczanie działa jak kliknięcie w Studio: pomija zablokowane (`Locked`) i całkiem
  przezroczyste części, a terenu nie zaznacza.
- Plugin działa tylko w trybie edycji (nie w Play).

### Gdy coś nie działa

| Problem | Co zrobić |
| --- | --- |
| Działa tylko jeden palec, szczypanie nic nie robi | Studio podaje dotyk jako mysz (patrz Diagnostyka). Zoom: stuknij i przeciągnij albo suwak; przesuwanie: joystick |
| Kamera w ogóle nie reaguje | Upewnij się, że status to „Aktywny” i że **Mysz i rysik** jest włączone; sprawdź w Diagnostyce, czy rosną liczniki |
| Status „Wstrzymany” | Wybrano inne narzędzie Studio – włącz ponownie przełącznikiem w oknie |
| Zoom włącza się zamiast przesuwania (lub odwrotnie) | Na początku gestu przesuwaj palce wyraźniej albo włącz **Zoom i pan razem** |
| Okno zasłania widok | Zwiń je strzałką albo przeciągnij za nagłówek |

## Dla deweloperów

```
src/
  init.server.luau          punkt wejścia: przycisk na pasku, cykl życia pluginu
  App.luau                  łączy wejście, gesty, kamerę, zaznaczanie i UI
  Settings.luau, Locale.luau, Config.luau
  Input/GestureRecognizer   dotyk → gesty (stuknięcia, obrót, zoom, pan, przytrzymanie)
  Input/TouchInput          UserInputService → GestureRecognizer (+ mysz jako palec)
  Camera/CameraController   orbita, pan, zoom, bezwładność, skupianie na obiekcie
  Selection/SelectionController
  UI/                       okno (Panel), nakładka (Overlay), komponenty, ikony gestów
tests/                      testy w Lune na atrapie API Roblox (tests/lib/World.luau)
tools/                      build .rbxmx, generator ikony, podgląd UI w przeglądarce
```

Narzędzia: [Lune](https://github.com/lune-org/lune), [StyLua](https://github.com/JohnnyMorganz/StyLua),
[Selene](https://github.com/Kampfkarren/selene), [Rojo](https://rojo.space) – wersje w `rokit.toml`.

```bash
lune run tests/run                  # testy (gesty, kamera, zaznaczanie, UI, cały plugin)
stylua src tests                    # formatowanie
selene generate-roblox-std && selene src   # lint
python3 tools/build_plugin.py       # odśwież dist/TouchPeak.rbxmx po zmianach w src
python3 tools/build_plugin.py --check

lune run tools/preview/export && node tools/preview/screenshot.js   # podgląd UI (Playwright)
```

Testy uruchamiają moduły pluginu w „udawanym” Studio: instancje są sprawdzane bazą
refleksji Roblox (zła nazwa lub typ właściwości = błąd), a raycasty, kamera i zaznaczenie są
symulowane. Prawdziwe zachowanie dotyku w Studio zależy od urządzenia, więc pierwsze
uruchomienie na ekranie dotykowym warto potraktować jako test i dostroić czułość w ustawieniach.
