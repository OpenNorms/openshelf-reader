// Renders ```mermaid blocks (emitted by ReaderCore as
// <pre><code class="language-mermaid">) as diagrams, coloured from the
// page's theme tokens. Runs after mermaid.min.js has been evaluated.
// A diagram that fails to parse falls back to showing its source.
(function () {
  var blocks = document.querySelectorAll('pre > code.language-mermaid');
  if (!blocks.length || !window.mermaid) return;
  var css = getComputedStyle(document.documentElement);
  function v(name) { return css.getPropertyValue('--' + name).trim(); }
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    suppressErrorRendering: true,
    theme: 'base',
    fontFamily: v('sans'),
    themeVariables: {
      background: v('bg'), fontFamily: v('sans'), textColor: v('ink'),
      primaryColor: v('panel2'), primaryTextColor: v('ink'),
      primaryBorderColor: v('amber'), secondaryColor: v('panel'),
      tertiaryColor: v('codebg'), lineColor: v('dim'),
      mainBkg: v('panel2'), nodeBorder: v('amber'),
      clusterBkg: v('panel'), clusterBorder: v('line'),
      edgeLabelBackground: v('bg'), titleColor: v('ink'),
      noteBkgColor: v('panel'), noteTextColor: v('ink'), noteBorderColor: v('line'),
      actorBkg: v('panel2'), actorBorder: v('amber'), actorTextColor: v('ink'),
      signalColor: v('dim'), signalTextColor: v('ink')
    }
  });
  var pairs = [];
  blocks.forEach(function (code) {
    var pre = code.parentNode;
    var div = document.createElement('div');
    div.className = 'mermaid';
    div.textContent = code.textContent;
    pre.parentNode.insertBefore(div, pre);
    pre.style.display = 'none';
    pairs.push({ div: div, pre: pre });
  });
  function settle() {
    pairs.forEach(function (p) {
      if (p.div.querySelector('svg')) { p.pre.remove(); }
      else { p.div.remove(); p.pre.style.display = ''; }
    });
  }
  mermaid.run({ nodes: pairs.map(function (p) { return p.div; }), suppressErrors: true })
    .then(settle, settle);
})();
