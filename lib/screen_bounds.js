// Prints "left top right bottom" (AppleScript window coordinates, origin at the top left of the
// menu-bar screen) of the usable area, excluding the menu bar and Dock, of the screen that
// contains the point given as two arguments. If no screen contains it, the menu-bar screen is used.
//
//   osascript -l JavaScript lib/screen_bounds.js <x> <y>
//
// Finder's desktop bounds are no use for this: with two displays they describe one rectangle
// spanning both.
ObjC.import('AppKit');

function run(argv) {
  const px = parseFloat(argv[0]);
  const py = parseFloat(argv[1]);
  const screens = $.NSScreen.screens;
  const main = screens.objectAtIndex(0); // index 0 is the screen with the menu bar and the origin
  const mainHeight = main.frame.size.height;
  const cy = mainHeight - py; // Cocoa's y grows upward, AppleScript's downward
  let pick = main;
  for (let i = 0; i < screens.count; i++) {
    const s = screens.objectAtIndex(i);
    const f = s.frame;
    if (px >= f.origin.x && px < f.origin.x + f.size.width && cy >= f.origin.y && cy < f.origin.y + f.size.height) {
      pick = s;
      break;
    }
  }
  const v = pick.visibleFrame;
  const left = v.origin.x;
  const right = v.origin.x + v.size.width;
  const top = mainHeight - (v.origin.y + v.size.height);
  const bottom = mainHeight - v.origin.y;
  return [left, top, right, bottom].map(Math.round).join(' ');
}
