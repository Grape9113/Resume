---
status: accepted
---
# One native panel and one application state owner

Resume is a Mac listening utility rather than a library-management application. The existing decision is a native menu-bar-only panel with one observable application state owner and an Audiobookshelf-specific integration; a web shell, generic provider architecture and separate management windows would add interaction and coordination costs without serving this product. The application-model seam carries end-to-end behavior tests, while native adapters and the panel receive their own integration checks.

Reconstructed from the implementation decisions in [the original specification](https://github.com/Grape9113/Resume/issues/1), the initial implementation and current composition. This records an existing choice; it does not endorse the unused core transition helper as the production state owner. See [architecture](../architecture.md).

Amended by [native Settings and conflict-only recovery](https://github.com/Grape9113/Resume/issues/12): Settings is a native SwiftUI Settings window, an explicit exception to the single-panel navigation decision. This supplies standard app-menu and Command-comma behavior and keeps diagnostic metadata out of playback. It shares the existing application model; playback remains a compact menu-bar panel.

Superseded in this respect by [the red interface amendment #15](https://github.com/Grape9113/Resume/issues/15): Settings returns to the same panel, retaining standard Command-comma/app-menu routing. The user prioritizes one stable keyboard-first object over a separate native Settings window. Escape replaces visible back navigation; the application state remains shared.
