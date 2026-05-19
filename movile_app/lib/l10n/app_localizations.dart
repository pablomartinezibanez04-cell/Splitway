import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Splitway'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Smart stopwatch for routes'**
  String get appTagline;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get commonClose;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get commonDiscard;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get languageSpanish;

  /// No description provided for @navEditor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get navEditor;

  /// No description provided for @navSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get navSession;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navRoutes.
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get navRoutes;

  /// No description provided for @drawerMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get drawerMenu;

  /// No description provided for @drawerDefaultUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get drawerDefaultUser;

  /// No description provided for @drawerSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get drawerSettings;

  /// No description provided for @drawerStats.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get drawerStats;

  /// No description provided for @drawerHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get drawerHelp;

  /// No description provided for @drawerSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get drawerSignOut;

  /// No description provided for @drawerSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get drawerSignIn;

  /// No description provided for @drawerAppVersion.
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String drawerAppVersion(String version);

  /// No description provided for @drawerSyncSynced.
  ///
  /// In en, this message translates to:
  /// **'SYNCED'**
  String get drawerSyncSynced;

  /// No description provided for @drawerSyncSyncedNow.
  ///
  /// In en, this message translates to:
  /// **'SYNCED · now'**
  String get drawerSyncSyncedNow;

  /// No description provided for @drawerSyncSyncedMinutes.
  ///
  /// In en, this message translates to:
  /// **'SYNCED · {minutes} min ago'**
  String drawerSyncSyncedMinutes(int minutes);

  /// No description provided for @drawerSyncSyncedAt.
  ///
  /// In en, this message translates to:
  /// **'SYNCED · {time}'**
  String drawerSyncSyncedAt(String time);

  /// No description provided for @drawerSyncSyncing.
  ///
  /// In en, this message translates to:
  /// **'SYNCING…'**
  String get drawerSyncSyncing;

  /// No description provided for @drawerSyncError.
  ///
  /// In en, this message translates to:
  /// **'SYNC ERROR'**
  String get drawerSyncError;

  /// No description provided for @drawerSyncOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get drawerSyncOffline;

  /// No description provided for @drawerSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get drawerSyncNow;

  /// No description provided for @loginBannerDefault.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get loginBannerDefault;

  /// No description provided for @loginEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get loginEmailHint;

  /// No description provided for @loginPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordHint;

  /// No description provided for @loginEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an email'**
  String get loginEmailRequired;

  /// No description provided for @loginEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email'**
  String get loginEmailInvalid;

  /// No description provided for @loginPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a password'**
  String get loginPasswordRequired;

  /// No description provided for @loginPasswordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Minimum 6 characters'**
  String get loginPasswordMinLength;

  /// No description provided for @loginSignInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginSignInButton;

  /// No description provided for @loginSignUpButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get loginSignUpButton;

  /// No description provided for @loginOrSeparator.
  ///
  /// In en, this message translates to:
  /// **'— or —'**
  String get loginOrSeparator;

  /// No description provided for @loginContinueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get loginContinueWithGoogle;

  /// No description provided for @loginToggleToSignUp.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get loginToggleToSignUp;

  /// No description provided for @loginToggleToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get loginToggleToSignIn;

  /// No description provided for @loginToggleSignUpAction.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get loginToggleSignUpAction;

  /// No description provided for @loginToggleSignInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginToggleSignInAction;

  /// No description provided for @loginSkipButton.
  ///
  /// In en, this message translates to:
  /// **'Continue without account'**
  String get loginSkipButton;

  /// No description provided for @loginConfirmationTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your inbox!'**
  String get loginConfirmationTitle;

  /// No description provided for @loginConfirmationBody.
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation link to\n{email}\n\nClick the link to activate your account and sign in.'**
  String loginConfirmationBody(String email);

  /// No description provided for @authErrorGoogleToken.
  ///
  /// In en, this message translates to:
  /// **'Could not retrieve Google token.'**
  String get authErrorGoogleToken;

  /// No description provided for @authErrorEmailAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered. Sign in.'**
  String get authErrorEmailAlreadyRegistered;

  /// No description provided for @authErrorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password.'**
  String get authErrorInvalidCredentials;

  /// No description provided for @authErrorEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email before signing in.'**
  String get authErrorEmailNotConfirmed;

  /// No description provided for @authErrorPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters.'**
  String get authErrorPasswordTooShort;

  /// No description provided for @authErrorNoConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection. Try again.'**
  String get authErrorNoConnection;

  /// No description provided for @authErrorUnexpected.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error. Try again.'**
  String get authErrorUnexpected;

  /// No description provided for @editorTitle.
  ///
  /// In en, this message translates to:
  /// **'Route editor'**
  String get editorTitle;

  /// No description provided for @editorNewRouteTooltip.
  ///
  /// In en, this message translates to:
  /// **'New route'**
  String get editorNewRouteTooltip;

  /// No description provided for @editorNewRouteButton.
  ///
  /// In en, this message translates to:
  /// **'New route'**
  String get editorNewRouteButton;

  /// No description provided for @editorNoRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'No routes yet'**
  String get editorNoRoutesTitle;

  /// No description provided for @editorNoRoutesMessage.
  ///
  /// In en, this message translates to:
  /// **'Create your first route to start timing.'**
  String get editorNoRoutesMessage;

  /// No description provided for @editorSectorsLabel.
  ///
  /// In en, this message translates to:
  /// **'Sectors'**
  String get editorSectorsLabel;

  /// No description provided for @editorSectorCenter.
  ///
  /// In en, this message translates to:
  /// **'Center: {lat}, {lng}'**
  String editorSectorCenter(String lat, String lng);

  /// No description provided for @editorStartFinishLabel.
  ///
  /// In en, this message translates to:
  /// **'Start / finish'**
  String get editorStartFinishLabel;

  /// No description provided for @editorCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created on {date}'**
  String editorCreatedAt(String date);

  /// No description provided for @editorDeleteRouteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete route'**
  String get editorDeleteRouteButton;

  /// No description provided for @editorDeleteRouteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete route'**
  String get editorDeleteRouteTitle;

  /// No description provided for @editorDeleteRouteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{routeName}\" and all its sessions?'**
  String editorDeleteRouteConfirm(String routeName);

  /// No description provided for @editorModeAppendPath.
  ///
  /// In en, this message translates to:
  /// **'Append path'**
  String get editorModeAppendPath;

  /// No description provided for @editorModeStartGate.
  ///
  /// In en, this message translates to:
  /// **'Start/finish'**
  String get editorModeStartGate;

  /// No description provided for @editorModeSectorGate.
  ///
  /// In en, this message translates to:
  /// **'Sector gate'**
  String get editorModeSectorGate;

  /// No description provided for @editorDrawingTitle.
  ///
  /// In en, this message translates to:
  /// **'Drawing: {draftName}'**
  String editorDrawingTitle(String draftName);

  /// No description provided for @editorCancelTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get editorCancelTooltip;

  /// No description provided for @editorCancelDrawingTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel drawing'**
  String get editorCancelDrawingTitle;

  /// No description provided for @editorCancelDrawingWarning.
  ///
  /// In en, this message translates to:
  /// **'Unsaved points will be discarded.'**
  String get editorCancelDrawingWarning;

  /// No description provided for @editorNoMapboxToken.
  ///
  /// In en, this message translates to:
  /// **'Mapbox token not configured. The interactive map is disabled; add a token and restart to draw.'**
  String get editorNoMapboxToken;

  /// No description provided for @editorSegmentPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get editorSegmentPath;

  /// No description provided for @editorSegmentStartFinish.
  ///
  /// In en, this message translates to:
  /// **'Start / finish'**
  String get editorSegmentStartFinish;

  /// No description provided for @editorSegmentAddSector.
  ///
  /// In en, this message translates to:
  /// **'Add sector'**
  String get editorSegmentAddSector;

  /// No description provided for @editorSegmentFreehand.
  ///
  /// In en, this message translates to:
  /// **'Freehand'**
  String get editorSegmentFreehand;

  /// No description provided for @editorModeFreehand.
  ///
  /// In en, this message translates to:
  /// **'Draw freehand'**
  String get editorModeFreehand;

  /// No description provided for @editorUndoFreehand.
  ///
  /// In en, this message translates to:
  /// **'Undo stroke'**
  String get editorUndoFreehand;

  /// No description provided for @editorUndoPoint.
  ///
  /// In en, this message translates to:
  /// **'Undo point'**
  String get editorUndoPoint;

  /// No description provided for @editorPathPoints.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No points} =1{1 point} other{{count} points}}'**
  String editorPathPoints(int count);

  /// No description provided for @editorStartGateUndefined.
  ///
  /// In en, this message translates to:
  /// **'No start'**
  String get editorStartGateUndefined;

  /// No description provided for @editorStartGateDefined.
  ///
  /// In en, this message translates to:
  /// **'Start defined'**
  String get editorStartGateDefined;

  /// No description provided for @editorSectorsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No sectors} =1{1 sector} other{{count} sectors}}'**
  String editorSectorsCount(int count);

  /// No description provided for @editorWaitingSecondPoint.
  ///
  /// In en, this message translates to:
  /// **'Waiting for 2nd point…'**
  String get editorWaitingSecondPoint;

  /// No description provided for @editorDifficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get editorDifficultyEasy;

  /// No description provided for @editorDifficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get editorDifficultyMedium;

  /// No description provided for @editorDifficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get editorDifficultyHard;

  /// No description provided for @editorHideSectors.
  ///
  /// In en, this message translates to:
  /// **'Hide sectors'**
  String get editorHideSectors;

  /// No description provided for @editorShowSectors.
  ///
  /// In en, this message translates to:
  /// **'Show sectors'**
  String get editorShowSectors;

  /// No description provided for @editorNoSectorsHint.
  ///
  /// In en, this message translates to:
  /// **'No sectors'**
  String get editorNoSectorsHint;

  /// No description provided for @editorClosedLoop.
  ///
  /// In en, this message translates to:
  /// **'Closed loop'**
  String get editorClosedLoop;

  /// No description provided for @editorOpenRoute.
  ///
  /// In en, this message translates to:
  /// **'Open route'**
  String get editorOpenRoute;

  /// No description provided for @editorRouteSavedSnack.
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\"'**
  String editorRouteSavedSnack(String name);

  /// No description provided for @editorSnapFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server to snap the route to roads. Showing straight segments until the connection is restored.'**
  String get editorSnapFailedMessage;

  /// No description provided for @editorRoutingProfileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Routing mode'**
  String get editorRoutingProfileTooltip;

  /// No description provided for @editorRoutingProfileDriving.
  ///
  /// In en, this message translates to:
  /// **'Road'**
  String get editorRoutingProfileDriving;

  /// No description provided for @editorRoutingProfileWalking.
  ///
  /// In en, this message translates to:
  /// **'Trail'**
  String get editorRoutingProfileWalking;

  /// No description provided for @editorRoutingProfileCycling.
  ///
  /// In en, this message translates to:
  /// **'Cycling'**
  String get editorRoutingProfileCycling;

  /// No description provided for @editorNewRouteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'New route'**
  String get editorNewRouteDialogTitle;

  /// No description provided for @editorEditRouteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit route'**
  String get editorEditRouteDialogTitle;

  /// No description provided for @editorNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get editorNameLabel;

  /// No description provided for @editorDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get editorDescriptionLabel;

  /// No description provided for @editorDifficultyLabel.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get editorDifficultyLabel;

  /// No description provided for @editorStartDrawingButton.
  ///
  /// In en, this message translates to:
  /// **'Start drawing'**
  String get editorStartDrawingButton;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyNoSessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'No sessions recorded yet'**
  String get historyNoSessionsTitle;

  /// No description provided for @historyNoSessionsMessage.
  ///
  /// In en, this message translates to:
  /// **'Go to the Session tab, pick a route, and tap \"Start\".'**
  String get historyNoSessionsMessage;

  /// No description provided for @historyDeletedRoute.
  ///
  /// In en, this message translates to:
  /// **'Deleted route'**
  String get historyDeletedRoute;

  /// No description provided for @historySessionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{date} · {lapCount, plural, =1{1 lap} other{{lapCount} laps}}{bestLap}'**
  String historySessionSubtitle(String date, int lapCount, String bestLap);

  /// No description provided for @historySessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get historySessionTitle;

  /// No description provided for @historyDeleteSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete session'**
  String get historyDeleteSessionTitle;

  /// No description provided for @historyIrreversibleWarning.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get historyIrreversibleWarning;

  /// No description provided for @historySessionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Session not found'**
  String get historySessionNotFound;

  /// No description provided for @historyLapsLabel.
  ///
  /// In en, this message translates to:
  /// **'Laps'**
  String get historyLapsLabel;

  /// No description provided for @historySectorsLabel.
  ///
  /// In en, this message translates to:
  /// **'Sectors'**
  String get historySectorsLabel;

  /// No description provided for @historySectorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lap {lapNum} · {speed}'**
  String historySectorSubtitle(int lapNum, String speed);

  /// No description provided for @historyDistanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get historyDistanceLabel;

  /// No description provided for @historyMaxSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Max speed'**
  String get historyMaxSpeedLabel;

  /// No description provided for @historyAvgSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Avg speed'**
  String get historyAvgSpeedLabel;

  /// No description provided for @sessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Live session'**
  String get sessionTitle;

  /// No description provided for @sessionNoRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'No routes to run'**
  String get sessionNoRoutesTitle;

  /// No description provided for @sessionNoRoutesMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a route in the Editor tab first to record a session.'**
  String get sessionNoRoutesMessage;

  /// No description provided for @sessionSelectRoute.
  ///
  /// In en, this message translates to:
  /// **'Select a route'**
  String get sessionSelectRoute;

  /// No description provided for @sessionTelemetrySource.
  ///
  /// In en, this message translates to:
  /// **'Telemetry source'**
  String get sessionTelemetrySource;

  /// No description provided for @sessionSourceSimulated.
  ///
  /// In en, this message translates to:
  /// **'Simulated'**
  String get sessionSourceSimulated;

  /// No description provided for @sessionSourceRealGps.
  ///
  /// In en, this message translates to:
  /// **'Real GPS'**
  String get sessionSourceRealGps;

  /// No description provided for @sessionStartButton.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get sessionStartButton;

  /// No description provided for @sessionSimulatedHint.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Simulate point\" to advance, or \"Auto lap\" to run a lap automatically.'**
  String get sessionSimulatedHint;

  /// No description provided for @sessionRealGpsHint.
  ///
  /// In en, this message translates to:
  /// **'Make sure location is enabled. Points are captured every second.'**
  String get sessionRealGpsHint;

  /// No description provided for @sessionSavedSnackBar.
  ///
  /// In en, this message translates to:
  /// **'Session saved'**
  String get sessionSavedSnackBar;

  /// No description provided for @sessionFinishButton.
  ///
  /// In en, this message translates to:
  /// **'Finish and save'**
  String get sessionFinishButton;

  /// No description provided for @sessionCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Session complete'**
  String get sessionCompleteTitle;

  /// No description provided for @sessionRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'Route: {routeName}'**
  String sessionRouteLabel(String routeName);

  /// No description provided for @sessionLapsLabel.
  ///
  /// In en, this message translates to:
  /// **'Laps'**
  String get sessionLapsLabel;

  /// No description provided for @sessionNewSessionButton.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get sessionNewSessionButton;

  /// No description provided for @sessionCurrentLapLabel.
  ///
  /// In en, this message translates to:
  /// **'Current lap'**
  String get sessionCurrentLapLabel;

  /// No description provided for @sessionLapNumber.
  ///
  /// In en, this message translates to:
  /// **'#{n}'**
  String sessionLapNumber(int n);

  /// No description provided for @sessionNoLapYet.
  ///
  /// In en, this message translates to:
  /// **'–'**
  String get sessionNoLapYet;

  /// No description provided for @sessionLapTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Lap time'**
  String get sessionLapTimeLabel;

  /// No description provided for @sessionBestLapLabel.
  ///
  /// In en, this message translates to:
  /// **'Best lap'**
  String get sessionBestLapLabel;

  /// No description provided for @sessionAwaitingStart.
  ///
  /// In en, this message translates to:
  /// **'Waiting for first finish-line crossing…'**
  String get sessionAwaitingStart;

  /// No description provided for @sessionCrossingSectors.
  ///
  /// In en, this message translates to:
  /// **'Crossing sectors…'**
  String get sessionCrossingSectors;

  /// No description provided for @sessionLastSector.
  ///
  /// In en, this message translates to:
  /// **'Last sector: {sectorId}'**
  String sessionLastSector(String sectorId);

  /// No description provided for @sessionDistanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get sessionDistanceLabel;

  /// No description provided for @sessionMaxSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Max speed'**
  String get sessionMaxSpeedLabel;

  /// No description provided for @sessionAvgSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Avg speed'**
  String get sessionAvgSpeedLabel;

  /// No description provided for @sessionLapsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Laps'**
  String get sessionLapsCountLabel;

  /// No description provided for @sessionPermissionGranted.
  ///
  /// In en, this message translates to:
  /// **'Location permission granted.'**
  String get sessionPermissionGranted;

  /// No description provided for @sessionPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied. Accept the system dialog or switch to \"Simulated\".'**
  String get sessionPermissionDenied;

  /// No description provided for @sessionPermissionPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission permanently blocked. Enable it manually in system settings.'**
  String get sessionPermissionPermanentlyDenied;

  /// No description provided for @sessionServicesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Location services disabled. Turn them on in system settings.'**
  String get sessionServicesDisabled;

  /// No description provided for @sessionGpsStatus.
  ///
  /// In en, this message translates to:
  /// **'Real GPS · {count, plural, =1{1 sample} other{{count} samples}}'**
  String sessionGpsStatus(int count);

  /// No description provided for @sessionGpsAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy: {accuracy} m · {lat}, {lng}'**
  String sessionGpsAccuracy(String accuracy, String lat, String lng);

  /// No description provided for @sessionAwaitingFirstFix.
  ///
  /// In en, this message translates to:
  /// **'Waiting for first fix…'**
  String get sessionAwaitingFirstFix;

  /// No description provided for @sessionSimulatePoint.
  ///
  /// In en, this message translates to:
  /// **'Simulate point'**
  String get sessionSimulatePoint;

  /// No description provided for @sessionPauseAuto.
  ///
  /// In en, this message translates to:
  /// **'Pause auto'**
  String get sessionPauseAuto;

  /// No description provided for @sessionAutoLap.
  ///
  /// In en, this message translates to:
  /// **'Auto lap'**
  String get sessionAutoLap;

  /// No description provided for @sessionSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Speed:'**
  String get sessionSpeedLabel;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageSection;

  /// No description provided for @settingsLanguageDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the app display language.'**
  String get settingsLanguageDescription;

  /// No description provided for @unitMeters.
  ///
  /// In en, this message translates to:
  /// **'{value} m'**
  String unitMeters(String value);

  /// No description provided for @unitKilometers.
  ///
  /// In en, this message translates to:
  /// **'{value} km'**
  String unitKilometers(String value);

  /// No description provided for @unitKmh.
  ///
  /// In en, this message translates to:
  /// **'{value} km/h'**
  String unitKmh(String value);

  /// No description provided for @mapNoRoute.
  ///
  /// In en, this message translates to:
  /// **'No route'**
  String get mapNoRoute;

  /// No description provided for @historyBestLapSuffix.
  ///
  /// In en, this message translates to:
  /// **' · best {duration}'**
  String historyBestLapSuffix(String duration);

  /// No description provided for @navFreeRide.
  ///
  /// In en, this message translates to:
  /// **'Free ride'**
  String get navFreeRide;

  /// No description provided for @freeRideTitle.
  ///
  /// In en, this message translates to:
  /// **'Free ride'**
  String get freeRideTitle;

  /// No description provided for @freeRideIdleTitle.
  ///
  /// In en, this message translates to:
  /// **'Ride without a destination'**
  String get freeRideIdleTitle;

  /// No description provided for @freeRideIdleMessage.
  ///
  /// In en, this message translates to:
  /// **'Record your path in real time without a predefined route. Speed, distance and position are tracked automatically.'**
  String get freeRideIdleMessage;

  /// No description provided for @freeRideStartButton.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get freeRideStartButton;

  /// No description provided for @freeRideElapsedLabel.
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get freeRideElapsedLabel;

  /// No description provided for @freeRideDistanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get freeRideDistanceLabel;

  /// No description provided for @freeRideSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get freeRideSpeedLabel;

  /// No description provided for @freeRideMaxSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Max speed'**
  String get freeRideMaxSpeedLabel;

  /// No description provided for @freeRideAvgSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Avg speed'**
  String get freeRideAvgSpeedLabel;

  /// No description provided for @freeRideFinishButton.
  ///
  /// In en, this message translates to:
  /// **'Finish ride'**
  String get freeRideFinishButton;

  /// No description provided for @freeRideCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Ride complete'**
  String get freeRideCompleteTitle;

  /// No description provided for @freeRideSavedSnackBar.
  ///
  /// In en, this message translates to:
  /// **'Free ride saved'**
  String get freeRideSavedSnackBar;

  /// No description provided for @freeRideSaveAsRouteButton.
  ///
  /// In en, this message translates to:
  /// **'Save as reusable route'**
  String get freeRideSaveAsRouteButton;

  /// No description provided for @freeRideDiscardButton.
  ///
  /// In en, this message translates to:
  /// **'Finish without saving route'**
  String get freeRideDiscardButton;

  /// No description provided for @freeRideNewRideButton.
  ///
  /// In en, this message translates to:
  /// **'New ride'**
  String get freeRideNewRideButton;

  /// No description provided for @freeRideSaveRouteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Save as route'**
  String get freeRideSaveRouteDialogTitle;

  /// No description provided for @freeRideNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get freeRideNameLabel;

  /// No description provided for @freeRideDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get freeRideDescriptionLabel;

  /// No description provided for @freeRideDifficultyLabel.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get freeRideDifficultyLabel;

  /// No description provided for @freeRideRouteSavedSnack.
  ///
  /// In en, this message translates to:
  /// **'Route \"{name}\" saved'**
  String freeRideRouteSavedSnack(String name);

  /// No description provided for @freeRidePointsLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 point} other{{count} points}}'**
  String freeRidePointsLabel(int count);

  /// No description provided for @historyNoEntriesTitle.
  ///
  /// In en, this message translates to:
  /// **'No activity recorded yet'**
  String get historyNoEntriesTitle;

  /// No description provided for @historyNoEntriesMessage.
  ///
  /// In en, this message translates to:
  /// **'Go for a free ride or record a session on a route.'**
  String get historyNoEntriesMessage;

  /// No description provided for @historyFreeRideLabel.
  ///
  /// In en, this message translates to:
  /// **'Free ride'**
  String get historyFreeRideLabel;

  /// No description provided for @historyFreeRideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{date} · {distance}'**
  String historyFreeRideSubtitle(String date, String distance);

  /// No description provided for @historyDeleteFreeRideTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete free ride'**
  String get historyDeleteFreeRideTitle;

  /// No description provided for @historyFreeRideTitle.
  ///
  /// In en, this message translates to:
  /// **'Free ride detail'**
  String get historyFreeRideTitle;

  /// No description provided for @historyRenameFreeRideTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename ride'**
  String get historyRenameFreeRideTitle;

  /// No description provided for @historyRenameFreeRideLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get historyRenameFreeRideLabel;

  /// No description provided for @historyRenamedSnack.
  ///
  /// In en, this message translates to:
  /// **'Name updated'**
  String get historyRenamedSnack;

  /// No description provided for @historyRenameRouteTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename route'**
  String get historyRenameRouteTitle;

  /// No description provided for @historyRenameRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get historyRenameRouteLabel;

  /// No description provided for @routesTitle.
  ///
  /// In en, this message translates to:
  /// **'My routes'**
  String get routesTitle;

  /// No description provided for @routesViewList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get routesViewList;

  /// No description provided for @routesViewGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get routesViewGrid;

  /// No description provided for @routesSessionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No sessions} =1{1 session} other{{count} sessions}}'**
  String routesSessionsCount(int count);

  /// No description provided for @routesBestLap.
  ///
  /// In en, this message translates to:
  /// **'Best: {time}'**
  String routesBestLap(String time);

  /// No description provided for @routesDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Route detail'**
  String get routesDetailTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
