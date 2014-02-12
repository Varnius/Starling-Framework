Starling Framework with deferred rendering support
==================================================

This fork of Starling is modified to support multiple render targets and has a deferred renderer extension added. Requires both Flash Player 11.6 beta player and corresponding playerglobal.swc as MRTs and some other features are currently supported only by 11.6 beta release of the runtime. You can get both [here](https://www.dropbox.com/sh/o7gmvxlze8s922y/h1sRx4JpYx).

Deferred renderer currently supports:

* Deferred point lights.
* Dynamic 2D shadows.

TODOs:

* Optimize rendering - some passes can be removed.
* Spotlights.

Example project can be found [here](https://github.com/Varnius/StarlingDynamicShadows2D)

