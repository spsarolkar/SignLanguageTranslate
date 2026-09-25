# Viewing the artboards

`support.js` is the canvas runtime the `.dc.html` files load. To view them in
a browser, serve this folder rather than opening files directly:

    cd docs/design/artboards && python3 -m http.server 8000
    # then open http://localhost:8000/Main.dc.html

`support.js` is a vendored runtime, not project code. Don't edit it, and agents
should not treat it as a source file.
