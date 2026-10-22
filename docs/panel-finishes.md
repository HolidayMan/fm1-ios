# FM-1 retail finishes

Rechecked 2026-10-17 against the manufacturer's [FM-1 product page](https://www.m-vave.com/product?id=fm-1) and [product data](https://www.m-vave.com/products-data.js). The official selector lists exactly Black, Purple, Orange, Black-Green, Cool Gray and White-Blue. Existing stored names remain stable; no separate Pink finish is listed. Retail listings corroborate the same combinations, but the manufacturer's full-size product photographs are the visual reference.

| Finish | Reference | Corrected pairing |
|---|---|---|
| Black | [Front photo](https://www.m-vave.com/images/productInfo/fm-1-1.webp) | Charcoal shell, dark charcoal silicone, light legends |
| Purple | [Front photo](https://www.m-vave.com/images/productInfo/fm-1-purple-1.webp) | Lilac shell, muted periwinkle silicone, dark control legends |
| Orange | [Front photo](https://www.m-vave.com/images/productInfo/fm-1-orange-1.webp) | Muted burnt-orange shell, terracotta silicone, dark control legends |
| Black-Green | [Front photo](https://www.m-vave.com/images/productInfo/fm-1-blackgreen-5.webp) | Charcoal shell, mint/turquoise silicone, dark control legends |
| Cool Gray | [Front photo](https://www.m-vave.com/images/productInfo/fm-1-coolgray-1.webp) | Warm light-gray shell, dark slate silicone, dark control legends |
| White-Blue | [Front photo](https://www.m-vave.com/images/productInfo/fm-1-whiteblue-1.webp) | Off-white shell, muted slate-blue silicone, dark control legends |

Every finish has black rotary knobs. The old implementation incorrectly tinted knobs with the silicone palette, kept a black keyboard surround for every finish, used pale legends on all buttons, made Purple pink, Orange saturated red-orange with charcoal keys, and Cool Gray beige with light gray keys. Those pairings are corrected. Keyboard surrounds now follow their silicone material. Smaller shading ranges avoid adding an artificial strong color shift from top to bottom. Press and firmware activity indicators retain the existing behavior and colors.

Colors are visually matched sRGB approximations from photographs, not measured factory color specifications. Lighting, exposure and phone display settings affect the perceived match. Manufacturer selector swatches are not used as the full product palette: for example Orange's swatch is #f15a24, while its actual gallery photographs show a substantially more muted body and differently colored silicone.

Photographs remain in ignored Research/ and are not bundled or redistributed. Only palette constants and material separation are shipped.

## Approved key illumination — 0.6.1 (18)

The owner selected the soft-halo design after comparing a real keyboard photo
with the native panel. The keyboard's existing central insert now displays the
firmware lamp; the separate bottom dash is removed. Function keys retain the top
strip. Cached padded sprites provide a local finish-tinted halo around a near-white
core. A dark recessed lip keeps the insert distinct from mid-tone silicone.

Raw firmware scan-duty normalization is unchanged. A continuous, monotonic
screen-only response lifts dim nonzero values: for normalized x, brightness is
x*1.03/(x+0.03). Off remains exactly0; no minimum-on floor or held-touch state is
introduced. This deliberately improves small-screen visibility rather than
claiming a photometrically linear copy of the physical LED. A dim state is a
generic firmware-controlled indication, with meaning determined by that
instrument; the mockup's old label “guide” did not add a scale/root feature.

Held feedback keeps the same key color, legend and perimeter, with immediate
cached inset shading. Current geometry/hit targets and firmware/audio timing
remain unchanged. Only bounds, display scale or finish regenerate artwork;
frame snapshots update lamp opacity, without runtime blur or shadow rendering.

## Per-finish illumination — 0.6.2 (19)

The external transport and side controls return to a plain black surround, with
no glass backplates. Glass sheets and their finish themes remain available inside
menus. Side targets retain44pt hit regions, move16pt below the top and clear the
physical side by12pt in either landscape orientation. The layout reuses the
existing safe-area gutter instead of reserving another full button-width column.

Black retains the exact18 emitter, halo, recess and response. Colored keys use
shallower0.75–1pt recesses instead of2pt and localized4.5–5pt halos instead of7pt:

| Finish | Core | Halo | Recess |
|---|---|---|---|
| Black | #F8FFF7 | #BAFFAD | #18251C |
| Purple | #FFF1FC | #E7A3E7 | #473962 |
| Orange | #FFF0D8 | #FFBF72 | #4C3026 |
| Black-Green | #E7FFF4 | #B8FFE8 | #244C48 |
| Cool Gray | #EAF4FF | #B8D8F4 | #293A46 |
| White-Blue | #E8F6FF | #9EDCFF | #294052 |

These are app optical treatments rather than measured hardware LED specifications.
Body/key materials, insert bounds, response curve, firmware duty, zero/off, input
and audio are unchanged. Recess/halo artwork remains cached at layout/finish
changes; display updates only change layer opacity. Native pixel, cache and
landscape checks are recorded separately in the19 verification receipt.
