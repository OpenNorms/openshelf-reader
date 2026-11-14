# Vendored

- `highlight.min.js` — highlight.js v11.11.1 (common-languages build),
  BSD-3-Clause, see `highlight.js.LICENSE.txt`. From
  cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js;
  sha256 c4a399dd6f488bc97a3546e3476747b3e714c99c57b9473154c6fb8d259b9381.
  Injected into page web views by `ReaderWebView`; colours come from the
  reader theme's tokens (`ReaderTheme.pageCSS`), not a highlight.js theme.
- `mermaid.min.js` — mermaid v11.4.1, MIT, see `mermaid.LICENSE.txt`.
  From cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js (identical
  on unpkg); sha256
  a43bc1afd446f9c4cc66ac5dd45d02e8d65e26fc5344ec0ef787f88d6ddb6f9e.
  Loaded only on pages that contain a ```mermaid block, by
  `ReaderWebView` + `App/mermaid-run.js`; diagram colours come from the
  reader theme's tokens.
