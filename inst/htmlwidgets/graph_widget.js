// graph_widget(): an explorer of the inline payload written by R. Rendering
// again (as Shiny does) replaces the explorer drawn before.
HTMLWidgets.widget({
  name: 'graph_widget',
  type: 'output',
  factory: function (el) {
    var drawn = null;
    return {
      renderValue: function (x) {
        if (drawn) drawn.then(function (gx) { if (gx) gx.destroy(); });
        el.textContent = '';
        // The explorer fills the widget, which htmlwidgets sizes
        var box = document.createElement('div');
        box.style.height = '100%';
        el.appendChild(box);
        drawn = GraphExplore.mount(box, { source: GraphExplore.inline(x.payload), storageKey: x.storageKey });
      },
      // The explorer follows its size itself
      resize: function () {}
    };
  }
});
