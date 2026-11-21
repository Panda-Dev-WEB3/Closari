---
name: closari-graphics
description: Create or revise Closari logos, social banners, editorial illustrations, campaign cards, market imagery, and motion assets using the project's approved artwork. Use for visual asset work on Closari. Website startup and backend integration use START-HERE.md.
---

# Closari graphics

Work from the extracted project root. Pick the closest finished asset below and view it at its intended size before drawing. Keep editable artwork beside its source family. Put only the web-sized export required by a page in `site/public`. The website already contains its production images.

## Choose the master

| Request | Start here | Preserve |
| --- | --- | --- |
| Closari logo or avatar | `artwork/Closari-C-folded-periwinkle.svg` and `artwork/Closari-C-folded-periwinkle-X.png` | The folded C, its two steps and the periwinkle field. Center the visible silhouette and check both square and circular crops at 32 and 48 px. Use the 1024 × 1024 risograph PNG for the printed avatar. |
| Cube or wordmark | `site/src/folded-c.svg`, `site/src/FoldedMark.jsx`, `site/public/fonts/MagicPixel-Regular.woff2` | Build depth from the original faces and keep the pause and reduced-motion behavior. Use the supplied Magic Pixel Regular for the Closari name. Use Geist for prose and Geist Mono for tickers, times and small captions. |
| Social banner | `artwork/Closari-Settlement-Hall-Riso-White-Tagline.png` and `artwork/source/print-components/` | Compose at 1500 × 500. The approved hall gives the board and figures room on the right and a quiet paper fade for the type on the left. Check the avatar overlap. Keep text, fade and contours editable. Use the blur-contour PNG to match the alternate finish. |
| Scrolling gallery, chapter exhibits and journal | `art-source/banner-icons`, `art-source/chapters`, `art-source/journal` | Gallery tiles are 720 × 720. Use one clear fintech object per chapter with the same camera angle, bevel, paper ground and inset. Chapter exhibits are 625 × 625 on mint plinths. Journal covers are landscape, 900 × 540. Use the active seven subjects from `site/src/stories.js`. |
| Stock or ETF | `site/src/markets.js`, `art-source/issuer-reliefs/faces`, `handoff/token-sources.md` | In Markets use a transparent 720 × 720 relief in the issuer’s original colors, centered by its visible outline after extrusion. The compact ticker uses its 192 × 192 PNG. The terminal instrument illustration is a separate 720 × 720 WebP. SPY uses State Street waves and QQQ uses its fund lettering. |
| Editorial scene or product explainer | `campaign/Filler-contact-sheet.jpg`, `campaign/Website-contact-sheet.jpg`, `campaign/source/still-art-direction.json` | The ten F-series scenes can tell a story through architecture, activity or a single object. The six T-series explain one product mechanic each. Start with the clean plate, leave a deliberate type area, and set the words using the editable layout. Square is 1080 × 1080 and landscape is 1620 × 1080. |
| Motion | `campaign/Film-contact-sheet.jpg`, `campaign/videos`, `campaign/motion-source/shot-direction.json` | Match the printed artwork between shots. Use a legible action such as the bell ringing or a range selection. The four atmosphere clips are six seconds. The 30-second film has its own supplied closing frame and folded-C overlay. |

## Match the drawing and materials

Use the settlement hall as the color and line reference. Draw fine indigo contours on warm ivory, mint architecture and periwinkle shadows. Use apricot or coral for a focal detail. Keep ink texture fine enough for figures and interface marks to read at small sizes. Give an object a visible face, a narrow sidewall and a short cast shadow; keep the light direction consistent across a set. On social assets, the white paper fade belongs to the banner composition and the opaque periwinkle belongs to the avatar. Use the transparent artwork for overlays.

For graphics displayed inside a page, take the surrounding colors and edge highlights from `site/src/edition.css`. The landing page opens in navy and the paper desk in white. Check both themes. Use subdued edges around quotes and order controls so that values and units carry the most contrast. Keep Robinhood Chain's transparent light and dark lockups in `site/public/network`.

## Fit the message to the format

Choose one subject and one job. A pricing card can use a gauge, a range example five bins, a settlement graphic a bell or a time stamp. Verify any ticker, price, example payout and session time against the active paper example or `handoff/briefs`. Historical campaign exports can show proposed product behavior. New public copy should distinguish the sample desk from planned live services.

For a new campaign card, inspect a neighboring PNG and its clean plate in `campaign/source/plates`. Adjust the composition for the requested aspect ratio, set accessible contrast and inspect the exported file at display size. Decks of media, identity experiments and intermediate print components belong outside the site’s public folder. The approved identity is recorded in `artwork/source/official-identity.txt`.

## Deliver the edit

Retain the master, export and asset-to-route mapping. Compare transparent edges on both a light and dark field. For website assets, open the actual page on a phone and desktop, check the hover or selected state where relevant, and rebuild the site. For optional campaign regeneration and the included asset formats, read `handoff/GRAPHICS.md`.
