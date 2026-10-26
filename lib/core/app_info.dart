/// App version shown in «Om» and included in feedback mails. Keep in
/// step with `version:` in pubspec.yaml.
const kAppVersion = '1.0.0+1';

const kFeedbackEmail = 'hei@norgeskompasset.no';

/// Firestore document with the tour calendar, written hourly by the
/// `refreshEvents` Cloud Function (functions/index.js).
const kEventsDoc = 'config/events';
