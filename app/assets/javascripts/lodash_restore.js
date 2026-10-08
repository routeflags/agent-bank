// The webpack bundles expose lodash4 on window._ (UMD global), which
// breaks sprockets-era code written for lodash2 semantics (implicit
// chain unwrap, `_.any`, non-throwing empty reduce). Load the vendored
// lodash2 AFTER the bundles to restore the global the legacy code expects.
//= require lodash.min
