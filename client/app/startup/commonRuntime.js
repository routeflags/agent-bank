/* eslint-env browser */
// Shared runtime for split client bundles.
//
// Exposes the globals that react-ujs / ChatPanel consumers rely on.
// Loaded BEFORE any per-app bundle (vendor-bundle -> common-bundle -> <app>-bundle).
import React from 'react';
import ReactDOM from 'react-dom';
import * as ActionCable from '@rails/actioncable';
import ReactOnRails from 'react-on-rails';

ReactOnRails.registerStore({});

if (typeof window !== 'undefined') {
  window.React = React;
  window.ReactDOM = ReactDOM;
  window.ActionCable = ActionCable;
}
