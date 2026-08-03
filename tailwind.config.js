/** @type {import('tailwindcss').Config} */
// The page is written in Nail, so the class names live in site.nail and
// nail/**/*.nail. static/js is scanned too - the theme toggle swaps classes
// there, in JavaScript.
// scripts/nail-build.sh regenerates static/styles/app.css on every build with
// the standalone CLI it downloads and caches under target/ (no npm needed):
//   tailwindcss -c tailwind.config.js -i styles/tailwind.css -o static/styles/app.css
module.exports = {
  // Class strategy, not media: the toggle in the header has to be able to
  // override the OS preference. static/js/site.js sets the class on <html>
  // before first paint, defaulting to whatever prefers-color-scheme says.
  darkMode: "class",
  content: ["./site.nail", "./nail/**/*.nail", "./static/js/**/*.js"],
  theme: {
    extend: {},
  },
  plugins: [],
};
