# wasm-game-directory
 
leaning towards grok suggestion. want to keep this one container probably

TODO:
- start simple
- each game has its own index.html and .wasm files + assets

LATER:
- lets index.html per game inherit higher level stuff like header, footer, style etc
- create a wasm-template.html that nginx uses to actually serve the .wasm files (each project would no longer need its own index.html and we would bundle all assets in .wasm)

LATERER:
- move to htmx and see if we like it better to get additional features (serve the .js dont use CDN)