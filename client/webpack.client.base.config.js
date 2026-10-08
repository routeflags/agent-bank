/* eslint-env node */

module.exports = {
  context: __dirname,
  entry: {

    // See use of 'vendor' in the CommonsChunkPlugin inclusion below.
    // vendor: [
    //   'es6-shim',
    //   'whatwg-fetch',
    // ],

    // This will contain the app entry points
    app: [
      './app/startup/clientRegistration',
    ],

    // Split per-app entries (code splitting — pages load only what they need).
    // Loaded after vendor-bundle + common-bundle via ClientAssetsHelper.
    common: ['./app/startup/commonRuntime'],
    topbar: ['./app/startup/entries/topbar'],
    chat_panel: ['./app/startup/entries/chatPanel'],
    onboarding: ['./app/startup/entries/onboarding'],
    search_page: ['./app/startup/entries/searchPage'],
    availability: ['./app/startup/entries/availability'],
  },
  resolve: {
    extensions: ['*', '.js'],
  },
  plugins: [],
  optimization: {
    minimize: false,
    splitChunks: {
      chunks: 'all',
      cacheGroups: {
        vendor: {
          // node_modules EXCEPT the heavy date/API deps (which go to
          // vendor_dates) — cacheGroups have no `exclude`, so negate in test.
          test: /[\\/]node_modules[\\/](?!moment|react-dates|react-with-|react-parent-portal|airbnb-|react-form|axios)/,
          name: 'vendor',
          chunks: 'initial',
          enforce: true,
        },
        // Date-picker & HTTP deps (moment/react-dates/axios/react-form) —
        // only pages whose entries import them load this chunk.
        vendor_dates: {
          test: /[\\/]node_modules[\\/](moment|react-dates|react-with-|react-parent-portal|airbnb-|react-form|axios)/,
          name: 'vendor_dates',
          chunks: 'initial',
          enforce: true,
        },
        // Shared first-party component tree (app/components, app/assets) —
        // extracted once instead of duplicated into every per-app entry.
        sections: {
          test: /[\\/]client[\\/]app[\\/](components|assets)[\\/]/,
          name: 'sections',
          chunks: 'initial',
          enforce: true,
        },
        // Disable webpack's remaining automatic shared/duplicate chunks —
        // Rails loads bundles via explicit sprockets tags (ClientAssetsHelper),
        // so each entrypoint must resolve to a known set of files.
        default: false,
        defaultVendors: false,
      },
    },
  },
  output: {
    filename: 'vendor-bundle.js',
  },
};
