// Observe Flutter's CDN-loaded map, without injecting or replacing the library.
module.exports = async function observe(page, name) {
 await page.addInitScript(({name}) => {
  const timer = setInterval(() => {
   const prototype = window.maplibregl?.Map?.prototype;
   if (!prototype?._render) return;
   clearInterval(timer);
   const render = prototype._render;
   prototype._render = function (...args) {
    if (!window[name]) {
     window[name] = this;
     window.__mapErrors = [];
     this.on('error', e => window.__mapErrors.push(String(e.error)));
    }
    return render.apply(this, args);
   };
  }, 1);
 }, {name});
};
