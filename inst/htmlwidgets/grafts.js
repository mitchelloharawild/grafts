// grafts(): an explorer of the payload written by R: every series, or the
// structure with a url that Shiny serves the series from. Rendering again
// (as Shiny does) replaces the explorer drawn before.
//
// In Shiny the explorer tells the app what it shows, as the inputs
// <id>_focus, _children, _pinned, _split, _view, _set, _theme and _measure,
// and takes the commands of graftsProxy() and grafts_update().
HTMLWidgets.widget({
  name: 'grafts',
  type: 'output',
  factory: function (el) {
    var drawn = null, box = null, storageKey = null;
    // Inputs holding series or variable names are decoded by input handlers in R
    var TYPES = { focus: 'grafts.series', children: 'grafts.series', pinned: 'grafts.series', split: 'grafts.names' };
    function onChange(name, value) {
      if (!window.HTMLWidgets.shinyMode || !window.Shiny || !el.id) return;
      Shiny.setInputValue(el.id + '_' + name + (TYPES[name] ? ':' + TYPES[name] : ''), value);
    }
    function mount(x, restore) {
      return Grafts.mount(box, { source: Grafts.fromPayload(x.payload), storageKey: x.storageKey, onChange: onChange, restore: restore });
    }
    var widget = {
      renderValue: function (x) {
        if (drawn) drawn.then(function (e) { if (e) e.destroy(); });
        el.textContent = '';
        // The explorer fills the widget, which htmlwidgets sizes
        box = document.createElement('div');
        box.style.height = '100%';
        el.appendChild(box);
        storageKey = x.storageKey;
        drawn = mount(x);
      },
      // Run a command of the app once the explorer is drawn
      command: function (cmd, args) {
        if (!drawn) return;
        drawn.then(function (e) { if (e) e.command(cmd, args); });
      },
      // Replace the data, keeping what the explorer shows when its series are the same
      update: function (payload) {
        if (!drawn) return;
        drawn = drawn.then(function (e) {
          var restore = e ? e.snapshot() : null;
          if (e) e.destroy();
          box.textContent = '';
          return mount({ payload: payload, storageKey: storageKey }, restore);
        });
      },
      // The explorer follows its size itself
      resize: function () {}
    };
    return widget;
  }
});

// Commands from graftsProxy(), sent to the widget of the output they name
if (window.Shiny) {
  Shiny.addCustomMessageHandler('grafts', function (msg) {
    var node = document.getElementById(msg.id), widget = node && HTMLWidgets.getInstance(node);
    if (!widget) return;
    if (msg.cmd === 'update') widget.update(msg.args.payload);
    else widget.command(msg.cmd, msg.args);
  });
}
