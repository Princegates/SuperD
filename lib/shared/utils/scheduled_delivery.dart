/// How soon a scheduled delivery counts as "coming up" - close enough that
/// a dispatcher should get a driver moving on it. Shared between the
/// admin dashboard's animated reminder banner and the pulsing badge on an
/// individual delivery card, so they agree on exactly when something
/// switches from routine to urgent.
const scheduledDueSoonThreshold = Duration(minutes: 30);
