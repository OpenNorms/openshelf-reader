// Page swipes, reported to the app via the "swipe" message handler.
//
//   left-to-right  = back     (quick flick, fires on release)
//   right-to-left  = forward  (the page follows the finger; release past
//                              the threshold to go, short of it to cancel;
//                              rubber-bands when there is no forward page)
//
// Ignored when the touch starts on something that scrolls sideways (code,
// tables, diagrams), within the left edge (iOS's own back gesture lives
// there), or while selecting text. The app sets
// window.__openshelfCanForward to say whether a forward page exists.
(function () {
  var EDGE = 24;            // px reserved for the system back gesture
  var LOCK = 10;            // px of movement before deciding the axis
  var BACK_DX = 70, BACK_MS = 700;
  var FORWARD_FRACTION = 0.28;  // of screen width
  var RUBBER = 0.2;             // drag factor with no forward page

  var sx = 0, sy = 0, st = 0, armed = false, axis = null, dragging = false;
  var body = document.body;

  function scrollsSideways(el) {
    for (; el && el !== document.body; el = el.parentElement) {
      if (el.scrollWidth > el.clientWidth + 1) {
        var o = getComputedStyle(el).overflowX;
        if (o === 'auto' || o === 'scroll') return true;
      }
    }
    return false;
  }
  function selecting() {
    return String(window.getSelection ? getSelection() : '').length > 0;
  }
  function canForward() { return window.__openshelfCanForward === true; }
  function place(x, animated, ms) {
    body.style.transition = animated ? 'transform ' + (ms || 220) + 'ms ease-out, opacity ' + (ms || 220) + 'ms ease-out' : 'none';
    body.style.transform = x ? 'translateX(' + x + 'px)' : '';
    body.style.opacity = x ? String(Math.max(0.55, 1 + x / (window.innerWidth * 1.6))) : '';
  }

  document.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 1) { armed = false; return; }
    var t = e.touches[0];
    sx = t.clientX; sy = t.clientY; st = Date.now();
    axis = null; dragging = false;
    armed = sx > EDGE && !scrollsSideways(e.target);
  }, { passive: true });

  document.addEventListener('touchmove', function (e) {
    if (!armed || e.touches.length !== 1) return;
    var t = e.touches[0];
    var dx = t.clientX - sx, dy = t.clientY - sy;
    if (!axis) {
      if (Math.abs(dx) < LOCK && Math.abs(dy) < LOCK) return;
      axis = Math.abs(dx) > 1.5 * Math.abs(dy) ? 'x' : 'y';
    }
    if (axis !== 'x' || selecting()) return;
    if (dx < 0) {
      dragging = true;
      e.preventDefault();  // hold the page still vertically while dragging
      place(canForward() ? dx : dx * RUBBER, false);
    } else if (dragging) {
      place(0, false);
    }
  }, { passive: false });

  function finish(e) {
    if (!armed) return;
    armed = false;
    var t = e.changedTouches[0];
    var dx = t.clientX - sx, dy = t.clientY - sy;

    if (dragging) {
      dragging = false;
      var go = canForward() && -dx > window.innerWidth * FORWARD_FRACTION;
      if (go) {
        place(-window.innerWidth * 0.45, true, 140);
        window.webkit.messageHandlers.swipe.postMessage('forward');
        // This page is now under the pushed one; restore it for when the
        // reader comes back.
        setTimeout(function () { place(0, false); }, 600);
      } else {
        place(0, true);
      }
      return;
    }

    if (axis !== 'x' || selecting()) return;
    if (dx > 0 && Date.now() - st <= BACK_MS && dx >= BACK_DX && Math.abs(dx) >= 2 * Math.abs(dy)) {
      window.webkit.messageHandlers.swipe.postMessage('back');
    }
  }
  document.addEventListener('touchend', finish, { passive: true });
  document.addEventListener('touchcancel', function () {
    if (dragging) place(0, true);
    armed = false; dragging = false;
  }, { passive: true });
})();
