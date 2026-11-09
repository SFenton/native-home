# Suggested recipes carousel (component)
> **What:** the hub's five paged pages of recipe cards, a header carrying "Page n of 5" and page dots. **Read when:** you change `SuggestedRecipesCarousel`, its layout rule or its paging.
- Mockup: [suggested-recipes-carousel.html](suggested-recipes-carousel.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Food/SuggestedRecipesCarousel.swift`, `FoodHubScreen.swift` (FoodSection), `HassDesign/NativePaging.swift`, `ImageCard.swift` · Spec: `.agents/pages/food/spec.md`, `ios.md` · Patterns: image-card, content-gate, dynamic-grid
- States covered: ready, page 3, loading (five placeholder pages), failed, empty, widths (351, 569 clipped, 802, 930 two rows), ax5
- Motion: paging (system scroll; adjustable action 0.3 s, jump under Reduce Motion), photo fade
- Devices: size class via the Device control; widths shown explicitly
- Open notes: no empty-answer copy exists (header only); on the hub the placeholders are hidden behind the gate unless it gives up after 10 s
