---
status: accepted
---
# One native panel and one application state owner

Resume is a Mac listening utility rather than a library-management application. The existing decision is a native menu-bar-only panel with one observable application state owner and an Audiobookshelf-specific integration; a web shell, generic provider architecture and separate management windows would add interaction and coordination costs without serving this product. The application-model seam carries end-to-end behavior tests, while native adapters and the panel receive their own integration checks.

Reconstructed from the implementation decisions in [the original specification](https://github.com/Grape9113/Resume/issues/1), the initial implementation and current composition. This records an existing choice; it does not endorse the unused core transition helper as the production state owner. See [architecture](../architecture.md).
