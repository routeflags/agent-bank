/* eslint-env browser */
// Per-app bundle: onboarding topbar + guide.
import ReactOnRails from 'react-on-rails';
import OnboardingTopBar from '../OnboardingTopBarApp';
import OnboardingGuideApp from '../OnboardingGuideApp';

ReactOnRails.register({
  OnboardingTopBar,
  OnboardingGuideApp,
});
