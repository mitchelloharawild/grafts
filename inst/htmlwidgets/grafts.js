// grafts(): an explorer of the inline payload written by R. Rendering
// again (as Shiny does) replaces the explorer drawn before.
//
// In Shiny the explorer tells the app what it shows, as the inputs
// <id>_focus, _children, _pinned, _split, _view, _set, _theme and _measure.
HTMLWidgets.widget({
  name: 'grafts',
  type: 'output',
  factory: function (el) {
    var drawn = null, box = null;
    // Inputs holding series or variable names are decoded by input handlers in R
    var TYPES = { focus: 'grafts.series', children: 'grafts.series', pinned: 'grafts.series', split: 'grafts.names' };
    function onChange(name, value) {
      if (!window.HTMLWidgets.shinyMode || !window.Shiny || !el.id) return;
      Shiny.setInputValue(el.id + '_' + name + (TYPES[name] ? ':' + TYPES[name] : ''), value);
    }
    function mount(x) {
      return Grafts.mount(box, { source: Grafts.inline(x.payload), storageKey: x.storageKey, onChange: onChange });
    }
    var widget = {
      renderValue: function (x) {
        if (drawn) drawn.then(function (e) { if (e) e.destroy(); });
        el.textContent = '';
        // The explorer fills the widget, which htmlwidgets sizes
        box = document.createElement('div');
        box.style.height = '100%';
        el.appendChild(box);
        drawn = mount(x);
      },
      // The explorer follows its size itself
      resize: function () {}
    };
    return widget;
  }
});
