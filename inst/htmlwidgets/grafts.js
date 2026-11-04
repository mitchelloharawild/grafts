// grafts(): an explorer of the inline payload written by R. Rendering
// again (as Shiny does) replaces the explorer drawn before.
HTMLWidgets.widget({
  name: 'grafts',
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
        drawn = Grafts.mount(box, { source: Grafts.inline(x.payload), storageKey: x.storageKey });
      },
      // The explorer follows its size itself
      resize: function () {}
    };
  }
});
