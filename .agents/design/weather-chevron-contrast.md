# Weather chevron contrast

> **What:** how the Home weather card's Previous and Next buttons look when they cannot page, chosen 2026-10-27 after the disabled chevron failed the contrast audit. **Read when:** touching `WeatherPagedCarousel`'s controls, or fading any disabled control.

Mockup: [weather-chevron-contrast.html](mockups/proposals/weather-chevron-contrast/weather-chevron-contrast.html) (also in the [hub](mockups/README.md)). It compares today with three options on a dark and a lighter card at Large and AX3; **A** is the decision.

## The bug

`ChromeJourneyTests.testChromePassesAccessibilityAudit` failed on iPad landscape with contrast 1.9 on "Previous 24-hour weather forecast". The button set `.opacity(0.4)` and used `.buttonStyle(.plain)`, which fades a disabled label again, so the glyph drew at about 20% white: a model of both fades predicts 1.94:1 and the screenshot measured 1.91:1 (`#4C4C4A` on `#1F1E1E`). It had always been faint; the one-row chip rail (`fix/duo-tabbar-chip-rail`) moved the card under the audit.

## The decision (owner, option A)

- The control fades once, to 55% of its drawing, through `WeatherCarouselControlStyle` (`WeatherCarouselControlStyle.swift`, used by `WeatherPagedCarousel`), which never fades the label again. A press dims it to `HassTokens.ControlState.pressedOpacity`.
- About 6.3:1 on the dark card and 4.8:1 on a bright wallpaper's card (enabled: 18:1). VoiceOver still reads "dimmed".
- Same circle, position and motion as before; only the ends are brighter.
- Scope: the weather card only (owner). Other controls that set their own disabled opacity (`BedSideSheet`, `VacuumAreaEditor`, `BedroomComponents`, `SettingsSection`, `PercentSliderRow` and the styles in MediaRemote, Vacuums and RoomDevices) were not changed; any of them on `.plain` may be faded twice the same way.

## Rules this adds

- Never pair `.buttonStyle(.plain)` with your own disabled opacity: the two multiply. Fade in the style (as here, `PrimaryButtonStyle` and the tile and row styles do) or not at all.
- A disabled control's glyph keeps 3:1 against what is directly behind it (WCAG 1.4.11 applies the bar to controls; this app holds disabled ones to it too). `WeatherViewTests.disabledCarouselControlKeepsThreeToOneContrast` pins the 55%.
