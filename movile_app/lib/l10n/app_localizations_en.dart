// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Splitway';

  @override
  String get appTagline => 'Smart stopwatch for routes';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonBack => 'Back';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Got it';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonDiscard => 'Discard';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSpanish => 'Spanish';

  @override
  String get navEditor => 'Editor';

  @override
  String get navSession => 'Session';

  @override
  String get navHistory => 'History';

  @override
  String get drawerMenu => 'Menu';

  @override
  String get drawerDefaultUser => 'User';

  @override
  String get drawerSettings => 'Settings';

  @override
  String get drawerStats => 'Statistics';

  @override
  String get drawerHelp => 'Help';

  @override
  String get drawerSignOut => 'Sign out';

  @override
  String get drawerSignIn => 'Sign in';

  @override
  String drawerAppVersion(String version) {
    return 'v$version';
  }

  @override
  String get drawerSyncSynced => 'SYNCED';

  @override
  String get drawerSyncSyncedNow => 'SYNCED · now';

  @override
  String drawerSyncSyncedMinutes(int minutes) {
    return 'SYNCED · $minutes min ago';
  }

  @override
  String drawerSyncSyncedAt(String time) {
    return 'SYNCED · $time';
  }

  @override
  String get drawerSyncSyncing => 'SYNCING…';

  @override
  String get drawerSyncError => 'SYNC ERROR';

  @override
  String get drawerSyncOffline => 'OFFLINE';

  @override
  String get drawerSyncNow => 'Sync now';

  @override
  String get loginBannerDefault => 'Sign in to continue';

  @override
  String get loginEmailHint => 'Email';

  @override
  String get loginPasswordHint => 'Password';

  @override
  String get loginEmailRequired => 'Enter an email';

  @override
  String get loginEmailInvalid => 'Invalid email';

  @override
  String get loginPasswordRequired => 'Enter a password';

  @override
  String get loginPasswordMinLength => 'Minimum 6 characters';

  @override
  String get loginSignInButton => 'Sign in';

  @override
  String get loginSignUpButton => 'Create account';

  @override
  String get loginOrSeparator => '— or —';

  @override
  String get loginContinueWithGoogle => 'Continue with Google';

  @override
  String get loginToggleToSignUp => 'Don\'t have an account? ';

  @override
  String get loginToggleToSignIn => 'Already have an account? ';

  @override
  String get loginToggleSignUpAction => 'Sign up';

  @override
  String get loginToggleSignInAction => 'Sign in';

  @override
  String get loginSkipButton => 'Continue without account';

  @override
  String get loginConfirmationTitle => 'Check your inbox!';

  @override
  String loginConfirmationBody(String email) {
    return 'We sent a confirmation link to\n$email\n\nClick the link to activate your account and sign in.';
  }

  @override
  String get authErrorGoogleToken => 'Could not retrieve Google token.';

  @override
  String get authErrorEmailAlreadyRegistered =>
      'This email is already registered. Sign in.';

  @override
  String get authErrorInvalidCredentials => 'Wrong email or password.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Confirm your email before signing in.';

  @override
  String get authErrorPasswordTooShort =>
      'Password must be at least 6 characters.';

  @override
  String get authErrorNoConnection => 'No connection. Try again.';

  @override
  String get authErrorUnexpected => 'Unexpected error. Try again.';

  @override
  String get editorTitle => 'Route editor';

  @override
  String get editorNewRouteTooltip => 'New route';

  @override
  String get editorNewRouteButton => 'New route';

  @override
  String get editorNoRoutesTitle => 'No routes yet';

  @override
  String get editorNoRoutesMessage =>
      'Create your first route to start timing.';

  @override
  String get editorSectorsLabel => 'Sectors';

  @override
  String editorSectorCenter(String lat, String lng) {
    return 'Center: $lat, $lng';
  }

  @override
  String get editorStartFinishLabel => 'Start / finish';

  @override
  String editorCreatedAt(String date) {
    return 'Created on $date';
  }

  @override
  String get editorDeleteRouteButton => 'Delete route';

  @override
  String get editorDeleteRouteTitle => 'Delete route';

  @override
  String editorDeleteRouteConfirm(String routeName) {
    return 'Delete \"$routeName\" and all its sessions?';
  }

  @override
  String get editorModeAppendPath => 'Append path';

  @override
  String get editorModeStartGate => 'Start/finish';

  @override
  String get editorModeSectorGate => 'Sector gate';

  @override
  String editorDrawingTitle(String draftName) {
    return 'Drawing: $draftName';
  }

  @override
  String get editorCancelTooltip => 'Cancel';

  @override
  String get editorCancelDrawingTitle => 'Cancel drawing';

  @override
  String get editorCancelDrawingWarning => 'Unsaved points will be discarded.';

  @override
  String get editorNoMapboxToken =>
      'Mapbox token not configured. The interactive map is disabled; add a token and restart to draw.';

  @override
  String get editorSegmentPath => 'Path';

  @override
  String get editorSegmentStartFinish => 'Start / finish';

  @override
  String get editorSegmentAddSector => 'Add sector';

  @override
  String get editorSegmentFreehand => 'Freehand';

  @override
  String get editorModeFreehand => 'Draw freehand';

  @override
  String get editorUndoFreehand => 'Undo stroke';

  @override
  String get editorUndoPoint => 'Undo point';

  @override
  String editorPathPoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points',
      one: '1 point',
      zero: 'No points',
    );
    return '$_temp0';
  }

  @override
  String get editorStartGateUndefined => 'No start';

  @override
  String get editorStartGateDefined => 'Start defined';

  @override
  String editorSectorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sectors',
      one: '1 sector',
      zero: 'No sectors',
    );
    return '$_temp0';
  }

  @override
  String get editorWaitingSecondPoint => 'Waiting for 2nd point…';

  @override
  String get editorDifficultyEasy => 'Easy';

  @override
  String get editorDifficultyMedium => 'Medium';

  @override
  String get editorDifficultyHard => 'Hard';

  @override
  String get editorHideSectors => 'Hide sectors';

  @override
  String get editorShowSectors => 'Show sectors';

  @override
  String get editorNoSectorsHint => 'No sectors';

  @override
  String get editorClosedLoop => 'Closed loop';

  @override
  String get editorOpenRoute => 'Open route';

  @override
  String editorRouteSavedSnack(String name) {
    return 'Saved \"$name\"';
  }

  @override
  String get editorSnapFailedMessage =>
      'Could not reach the server to snap the route to roads. Showing straight segments until the connection is restored.';

  @override
  String get editorNewRouteDialogTitle => 'New route';

  @override
  String get editorEditRouteDialogTitle => 'Edit route';

  @override
  String get editorNameLabel => 'Name';

  @override
  String get editorDescriptionLabel => 'Description (optional)';

  @override
  String get editorDifficultyLabel => 'Difficulty';

  @override
  String get editorStartDrawingButton => 'Start drawing';

  @override
  String get historyTitle => 'History';

  @override
  String get historyNoSessionsTitle => 'No sessions recorded yet';

  @override
  String get historyNoSessionsMessage =>
      'Go to the Session tab, pick a route, and tap \"Start\".';

  @override
  String get historyDeletedRoute => 'Deleted route';

  @override
  String historySessionSubtitle(String date, int lapCount, String bestLap) {
    String _temp0 = intl.Intl.pluralLogic(
      lapCount,
      locale: localeName,
      other: '$lapCount laps',
      one: '1 lap',
    );
    return '$date · $_temp0$bestLap';
  }

  @override
  String get historySessionTitle => 'Session';

  @override
  String get historyDeleteSessionTitle => 'Delete session';

  @override
  String get historyIrreversibleWarning => 'This action cannot be undone.';

  @override
  String get historySessionNotFound => 'Session not found';

  @override
  String get historyLapsLabel => 'Laps';

  @override
  String get historySectorsLabel => 'Sectors';

  @override
  String historySectorSubtitle(int lapNum, String speed) {
    return 'Lap $lapNum · $speed';
  }

  @override
  String get historyDistanceLabel => 'Distance';

  @override
  String get historyMaxSpeedLabel => 'Max speed';

  @override
  String get historyAvgSpeedLabel => 'Avg speed';

  @override
  String get sessionTitle => 'Live session';

  @override
  String get sessionNoRoutesTitle => 'No routes to run';

  @override
  String get sessionNoRoutesMessage =>
      'Create a route in the Editor tab first to record a session.';

  @override
  String get sessionSelectRoute => 'Select a route';

  @override
  String get sessionTelemetrySource => 'Telemetry source';

  @override
  String get sessionSourceSimulated => 'Simulated';

  @override
  String get sessionSourceRealGps => 'Real GPS';

  @override
  String get sessionStartButton => 'Start recording';

  @override
  String get sessionSimulatedHint =>
      'Tap \"Simulate point\" to advance, or \"Auto lap\" to run a lap automatically.';

  @override
  String get sessionRealGpsHint =>
      'Make sure location is enabled. Points are captured every second.';

  @override
  String get sessionSavedSnackBar => 'Session saved';

  @override
  String get sessionFinishButton => 'Finish and save';

  @override
  String get sessionCompleteTitle => 'Session complete';

  @override
  String sessionRouteLabel(String routeName) {
    return 'Route: $routeName';
  }

  @override
  String get sessionLapsLabel => 'Laps';

  @override
  String get sessionNewSessionButton => 'New session';

  @override
  String get sessionCurrentLapLabel => 'Current lap';

  @override
  String sessionLapNumber(int n) {
    return '#$n';
  }

  @override
  String get sessionNoLapYet => '–';

  @override
  String get sessionLapTimeLabel => 'Lap time';

  @override
  String get sessionBestLapLabel => 'Best lap';

  @override
  String get sessionAwaitingStart => 'Waiting for first finish-line crossing…';

  @override
  String get sessionCrossingSectors => 'Crossing sectors…';

  @override
  String sessionLastSector(String sectorId) {
    return 'Last sector: $sectorId';
  }

  @override
  String get sessionDistanceLabel => 'Distance';

  @override
  String get sessionMaxSpeedLabel => 'Max speed';

  @override
  String get sessionAvgSpeedLabel => 'Avg speed';

  @override
  String get sessionLapsCountLabel => 'Laps';

  @override
  String get sessionPermissionGranted => 'Location permission granted.';

  @override
  String get sessionPermissionDenied =>
      'Location permission denied. Accept the system dialog or switch to \"Simulated\".';

  @override
  String get sessionPermissionPermanentlyDenied =>
      'Permission permanently blocked. Enable it manually in system settings.';

  @override
  String get sessionServicesDisabled =>
      'Location services disabled. Turn them on in system settings.';

  @override
  String sessionGpsStatus(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count samples',
      one: '1 sample',
    );
    return 'Real GPS · $_temp0';
  }

  @override
  String sessionGpsAccuracy(String accuracy, String lat, String lng) {
    return 'Accuracy: $accuracy m · $lat, $lng';
  }

  @override
  String get sessionAwaitingFirstFix => 'Waiting for first fix…';

  @override
  String get sessionSimulatePoint => 'Simulate point';

  @override
  String get sessionPauseAuto => 'Pause auto';

  @override
  String get sessionAutoLap => 'Auto lap';

  @override
  String get sessionSpeedLabel => 'Speed:';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguageSection => 'Language';

  @override
  String get settingsLanguageDescription => 'Choose the app display language.';

  @override
  String unitMeters(String value) {
    return '$value m';
  }

  @override
  String unitKilometers(String value) {
    return '$value km';
  }

  @override
  String unitKmh(String value) {
    return '$value km/h';
  }

  @override
  String get mapNoRoute => 'No route';

  @override
  String historyBestLapSuffix(String duration) {
    return ' · best $duration';
  }

  @override
  String get navFreeRide => 'Free ride';

  @override
  String get freeRideTitle => 'Free ride';

  @override
  String get freeRideIdleTitle => 'Ride without a destination';

  @override
  String get freeRideIdleMessage =>
      'Record your path in real time without a predefined route. Speed, distance and position are tracked automatically.';

  @override
  String get freeRideStartButton => 'Start recording';

  @override
  String get freeRideElapsedLabel => 'Elapsed';

  @override
  String get freeRideDistanceLabel => 'Distance';

  @override
  String get freeRideSpeedLabel => 'Speed';

  @override
  String get freeRideMaxSpeedLabel => 'Max speed';

  @override
  String get freeRideAvgSpeedLabel => 'Avg speed';

  @override
  String get freeRideFinishButton => 'Finish ride';

  @override
  String get freeRideCompleteTitle => 'Ride complete';

  @override
  String get freeRideSavedSnackBar => 'Free ride saved';

  @override
  String get freeRideSaveAsRouteButton => 'Save as reusable route';

  @override
  String get freeRideDiscardButton => 'Finish without saving route';

  @override
  String get freeRideNewRideButton => 'New ride';

  @override
  String get freeRideSaveRouteDialogTitle => 'Save as route';

  @override
  String get freeRideNameLabel => 'Name';

  @override
  String get freeRideDescriptionLabel => 'Description (optional)';

  @override
  String get freeRideDifficultyLabel => 'Difficulty';

  @override
  String freeRideRouteSavedSnack(String name) {
    return 'Route \"$name\" saved';
  }

  @override
  String freeRidePointsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points',
      one: '1 point',
    );
    return '$_temp0';
  }

  @override
  String get historyNoEntriesTitle => 'No activity recorded yet';

  @override
  String get historyNoEntriesMessage =>
      'Go for a free ride or record a session on a route.';

  @override
  String get historyFreeRideLabel => 'Free ride';

  @override
  String historyFreeRideSubtitle(String date, String distance) {
    return '$date · $distance';
  }

  @override
  String get historyDeleteFreeRideTitle => 'Delete free ride';

  @override
  String get historyFreeRideTitle => 'Free ride detail';

  @override
  String get historyRenameFreeRideTitle => 'Rename ride';

  @override
  String get historyRenameFreeRideLabel => 'Name';

  @override
  String get historyRenamedSnack => 'Name updated';

  @override
  String get historyRenameRouteTitle => 'Rename route';

  @override
  String get historyRenameRouteLabel => 'Name';

  @override
  String get profileTitle => 'My profile';

  @override
  String get profileNicknameLabel => 'Nickname';

  @override
  String get profileBioLabel => 'About me';

  @override
  String get profileBioHint => 'Tell others about yourself…';

  @override
  String get profileChangeAvatar => 'Change photo';

  @override
  String get profileSaved => 'Profile saved';

  @override
  String get profileNicknameCooldown => 'You can change your nickname again in:';

  @override
  String profileNicknameCooldownDays(int days) {
    return '$days ${days == 1 ? 'day' : 'days'}';
  }

  @override
  String profileNicknameCooldownHours(int hours) {
    return '$hours ${hours == 1 ? 'hour' : 'hours'}';
  }

  @override
  String get profileNicknameRequired => 'Enter a nickname';

  @override
  String get profileNicknameMinLength => 'Minimum 2 characters';

  @override
  String get profileNicknameTooLong => 'Maximum 24 characters';

  @override
  String get profileNicknameUpdated => 'Nickname updated';

  @override
  String get profileBioUpdated => 'Bio updated';

  @override
  String get profileAvatarUpdated => 'Photo updated';

  @override
  String get profileErrorCooldown => 'Wait 3 days between nickname changes.';

  @override
  String get profileErrorUnexpected => 'Something went wrong. Try again.';

  @override
  String get loginNicknameHint => 'Nickname';

  @override
  String get loginNicknameRequired => 'Choose a nickname';

  @override
  String get loginNicknameMinLength => 'Minimum 2 characters';

  @override
  String get drawerProfile => 'Profile';
}
