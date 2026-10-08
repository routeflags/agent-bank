/* eslint-env browser */
// Per-app bundle: availability / working-hours editors.
import ReactOnRails from 'react-on-rails';
import ManageAvailabilityApp from '../ManageAvailabilityApp';
import ListingWorkingHoursApp from '../ListingWorkingHoursApp';

ReactOnRails.register({
  ManageAvailabilityApp,
  ListingWorkingHoursApp,
});
