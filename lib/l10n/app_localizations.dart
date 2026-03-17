import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'XAssistant'**
  String get appTitle;

  /// No description provided for @appSubtitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant for xassistant'**
  String get appSubtitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get navTasks;

  /// No description provided for @navSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get navSchedule;

  /// No description provided for @navMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get navMessages;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @pairNewDevice.
  ///
  /// In en, this message translates to:
  /// **'Pair New Device'**
  String get pairNewDevice;

  /// No description provided for @setManualProxy.
  ///
  /// In en, this message translates to:
  /// **'Set Manual Proxy'**
  String get setManualProxy;

  /// No description provided for @bypassPairingHint.
  ///
  /// In en, this message translates to:
  /// **'Bypass pairing to connect directly'**
  String get bypassPairingHint;

  /// No description provided for @connectedDevice.
  ///
  /// In en, this message translates to:
  /// **'Connected Device'**
  String get connectedDevice;

  /// No description provided for @deviceInfo.
  ///
  /// In en, this message translates to:
  /// **'{deviceName} ({ip}:{port})'**
  String deviceInfo(Object deviceName, Object ip, Object port);

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @connectionMayHaveIssue.
  ///
  /// In en, this message translates to:
  /// **'Connection may have an issue'**
  String get connectionMayHaveIssue;

  /// No description provided for @diagnose.
  ///
  /// In en, this message translates to:
  /// **'Diagnose'**
  String get diagnose;

  /// No description provided for @connectionDiagnosis.
  ///
  /// In en, this message translates to:
  /// **'Connection diagnosis'**
  String get connectionDiagnosis;

  /// No description provided for @checkingConnection.
  ///
  /// In en, this message translates to:
  /// **'Checking connection...'**
  String get checkingConnection;

  /// No description provided for @errorLoadingConnection.
  ///
  /// In en, this message translates to:
  /// **'Error loading connection'**
  String get errorLoadingConnection;

  /// No description provided for @proxyConfig.
  ///
  /// In en, this message translates to:
  /// **'Proxy config'**
  String get proxyConfig;

  /// No description provided for @proxyConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start, stop proxy and manage launch params'**
  String get proxyConfigSubtitle;

  /// No description provided for @openclawSkills.
  ///
  /// In en, this message translates to:
  /// **'OpenClaw skills'**
  String get openclawSkills;

  /// No description provided for @addSkillPath.
  ///
  /// In en, this message translates to:
  /// **'Add skill path'**
  String get addSkillPath;

  /// No description provided for @cannotLoadSkillPaths.
  ///
  /// In en, this message translates to:
  /// **'Cannot load skill paths'**
  String get cannotLoadSkillPaths;

  /// No description provided for @xAssistantProjects.
  ///
  /// In en, this message translates to:
  /// **'XAssistant / Projects'**
  String get xAssistantProjects;

  /// No description provided for @manageProjects.
  ///
  /// In en, this message translates to:
  /// **'Manage projects'**
  String get manageProjects;

  /// No description provided for @projectsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View, add and edit projects'**
  String get projectsSubtitle;

  /// No description provided for @projectsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} projects'**
  String projectsCount(Object count);

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @textToSpeech.
  ///
  /// In en, this message translates to:
  /// **'Text-to-Speech'**
  String get textToSpeech;

  /// No description provided for @readAloud.
  ///
  /// In en, this message translates to:
  /// **'Read responses aloud'**
  String get readAloud;

  /// No description provided for @speechRate.
  ///
  /// In en, this message translates to:
  /// **'Speech rate'**
  String get speechRate;

  /// No description provided for @normal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normal;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @systemNotification.
  ///
  /// In en, this message translates to:
  /// **'System notification'**
  String get systemNotification;

  /// No description provided for @systemNotificationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Push when task completes'**
  String get systemNotificationSubtitle;

  /// No description provided for @viewMessages.
  ///
  /// In en, this message translates to:
  /// **'View messages'**
  String get viewMessages;

  /// No description provided for @viewNotificationHistory.
  ///
  /// In en, this message translates to:
  /// **'View in-app notification history'**
  String get viewNotificationHistory;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @github.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get github;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @path.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get path;

  /// No description provided for @pathHint.
  ///
  /// In en, this message translates to:
  /// **'/path/to/skills or ~/skills'**
  String get pathHint;

  /// No description provided for @disconnectConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnectConfirmTitle;

  /// No description provided for @disconnectConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to disconnect from this computer?'**
  String get disconnectConfirmMessage;

  /// No description provided for @resetPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset PIN'**
  String get resetPinTitle;

  /// No description provided for @resetPinMessage.
  ///
  /// In en, this message translates to:
  /// **'Reset will invalidate the old PIN. You need to re-pair with the new PIN.'**
  String get resetPinMessage;

  /// No description provided for @currentPin.
  ///
  /// In en, this message translates to:
  /// **'Current PIN: {pin}'**
  String currentPin(Object pin);

  /// No description provided for @confirmReset.
  ///
  /// In en, this message translates to:
  /// **'Confirm reset'**
  String get confirmReset;

  /// No description provided for @pinResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'PIN reset to: {pin}'**
  String pinResetSuccess(Object pin);

  /// No description provided for @resetFailed.
  ///
  /// In en, this message translates to:
  /// **'Reset failed: {error}'**
  String resetFailed(Object error);

  /// No description provided for @editConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit connection'**
  String get editConnection;

  /// No description provided for @ipAddress.
  ///
  /// In en, this message translates to:
  /// **'IP address'**
  String get ipAddress;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @pinCode.
  ///
  /// In en, this message translates to:
  /// **'PIN code'**
  String get pinCode;

  /// No description provided for @pinUseSavedHint.
  ///
  /// In en, this message translates to:
  /// **'Use saved PIN (or enter new)'**
  String get pinUseSavedHint;

  /// No description provided for @pinEnterHint.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get pinEnterHint;

  /// No description provided for @leaveEmptyUseSavedPin.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use saved PIN'**
  String get leaveEmptyUseSavedPin;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @pairFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to pair: {error}'**
  String pairFailed(Object error);

  /// No description provided for @pleaseFillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill all fields'**
  String get pleaseFillAllFields;

  /// No description provided for @diagnosisCurrentState.
  ///
  /// In en, this message translates to:
  /// **'Current state'**
  String get diagnosisCurrentState;

  /// No description provided for @diagnosisSavedIp.
  ///
  /// In en, this message translates to:
  /// **'Saved IP'**
  String get diagnosisSavedIp;

  /// No description provided for @diagnosisFailCount.
  ///
  /// In en, this message translates to:
  /// **'Consecutive failures'**
  String get diagnosisFailCount;

  /// No description provided for @diagnosisFailCountValue.
  ///
  /// In en, this message translates to:
  /// **'{count} times'**
  String diagnosisFailCountValue(Object count);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @rePair.
  ///
  /// In en, this message translates to:
  /// **'Re-pair'**
  String get rePair;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @stateUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get stateUnknown;

  /// No description provided for @stateConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get stateConnected;

  /// No description provided for @stateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get stateConnecting;

  /// No description provided for @stateNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get stateNetworkError;

  /// No description provided for @stateIpChanged.
  ///
  /// In en, this message translates to:
  /// **'IP may have changed'**
  String get stateIpChanged;

  /// No description provided for @stateAuthError.
  ///
  /// In en, this message translates to:
  /// **'Auth error'**
  String get stateAuthError;

  /// No description provided for @pinCodeReusable.
  ///
  /// In en, this message translates to:
  /// **'PIN: {pin} (reusable)'**
  String pinCodeReusable(Object pin);

  /// No description provided for @resetPinTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset PIN'**
  String get resetPinTooltip;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @taskList.
  ///
  /// In en, this message translates to:
  /// **'Task list'**
  String get taskList;

  /// No description provided for @taskDetail.
  ///
  /// In en, this message translates to:
  /// **'Task detail'**
  String get taskDetail;

  /// No description provided for @taskNotFound.
  ///
  /// In en, this message translates to:
  /// **'Task not found'**
  String get taskNotFound;

  /// No description provided for @addTask.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get addTask;

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTask;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get filterPending;

  /// No description provided for @filterInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get filterInProgress;

  /// No description provided for @filterCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get filterCompleted;

  /// No description provided for @emptyTasksAll.
  ///
  /// In en, this message translates to:
  /// **'No tasks'**
  String get emptyTasksAll;

  /// No description provided for @emptyTasksPending.
  ///
  /// In en, this message translates to:
  /// **'No pending tasks'**
  String get emptyTasksPending;

  /// No description provided for @emptyTasksInProgress.
  ///
  /// In en, this message translates to:
  /// **'No in-progress tasks'**
  String get emptyTasksInProgress;

  /// No description provided for @emptyTasksCompleted.
  ///
  /// In en, this message translates to:
  /// **'No completed tasks yet'**
  String get emptyTasksCompleted;

  /// No description provided for @dashboardInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get dashboardInProgress;

  /// No description provided for @dashboardPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get dashboardPending;

  /// No description provided for @greetingNight.
  ///
  /// In en, this message translates to:
  /// **'Late night 🌙'**
  String get greetingNight;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning ☀️'**
  String get greetingMorning;

  /// No description provided for @greetingNoon.
  ///
  /// In en, this message translates to:
  /// **'Good noon 🌤'**
  String get greetingNoon;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon ⛅'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening 🌙'**
  String get greetingEvening;

  /// No description provided for @scheduleArrow.
  ///
  /// In en, this message translates to:
  /// **'Schedule →'**
  String get scheduleArrow;

  /// No description provided for @weekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySun;

  /// No description provided for @weekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySat;

  /// No description provided for @typeCommand.
  ///
  /// In en, this message translates to:
  /// **'Type a command...'**
  String get typeCommand;

  /// No description provided for @cancelTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelTooltip;

  /// No description provided for @historyTooltip.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTooltip;

  /// No description provided for @notConnectedToServer.
  ///
  /// In en, this message translates to:
  /// **'Not connected to server'**
  String get notConnectedToServer;

  /// No description provided for @waitForConversation.
  ///
  /// In en, this message translates to:
  /// **'Please wait for the current conversation to finish'**
  String get waitForConversation;

  /// No description provided for @fixErrors.
  ///
  /// In en, this message translates to:
  /// **'Fix errors'**
  String get fixErrors;

  /// No description provided for @runTests.
  ///
  /// In en, this message translates to:
  /// **'Run tests'**
  String get runTests;

  /// No description provided for @explainCode.
  ///
  /// In en, this message translates to:
  /// **'Explain code'**
  String get explainCode;

  /// No description provided for @quickResponse.
  ///
  /// In en, this message translates to:
  /// **'Quick response'**
  String get quickResponse;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection error. Please check your connection.'**
  String get connectionError;

  /// No description provided for @disconnectedFromServer.
  ///
  /// In en, this message translates to:
  /// **'Disconnected from server.'**
  String get disconnectedFromServer;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @agentBackendError.
  ///
  /// In en, this message translates to:
  /// **'Agent backend: {error}'**
  String agentBackendError(Object error);

  /// No description provided for @agentBackendDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Agent backend disconnected. Replies may be delayed.'**
  String get agentBackendDisconnected;

  /// No description provided for @fixErrorsCommand.
  ///
  /// In en, this message translates to:
  /// **'Fix any errors in the current file'**
  String get fixErrorsCommand;

  /// No description provided for @runTestsCommand.
  ///
  /// In en, this message translates to:
  /// **'Run the tests'**
  String get runTestsCommand;

  /// No description provided for @explainCodeCommand.
  ///
  /// In en, this message translates to:
  /// **'Explain this code'**
  String get explainCodeCommand;

  /// No description provided for @commandHistory.
  ///
  /// In en, this message translates to:
  /// **'Command history'**
  String get commandHistory;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all command history? This cannot be undone.'**
  String get clearHistoryConfirm;

  /// No description provided for @noCommandHistory.
  ///
  /// In en, this message translates to:
  /// **'No command history yet'**
  String get noCommandHistory;

  /// No description provided for @messages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messages;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noNotifications;

  /// No description provided for @notificationsHint.
  ///
  /// In en, this message translates to:
  /// **'You will get notifications here when tasks complete'**
  String get notificationsHint;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @markAllReadConfirm.
  ///
  /// In en, this message translates to:
  /// **'Mark all messages as read?'**
  String get markAllReadConfirm;

  /// No description provided for @clearMessages.
  ///
  /// In en, this message translates to:
  /// **'Clear messages'**
  String get clearMessages;

  /// No description provided for @clearMessagesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all messages? This cannot be undone.'**
  String get clearMessagesConfirm;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @connectToComputer.
  ///
  /// In en, this message translates to:
  /// **'Connect to computer'**
  String get connectToComputer;

  /// No description provided for @startProxyFirst.
  ///
  /// In en, this message translates to:
  /// **'Start/configure proxy first'**
  String get startProxyFirst;

  /// No description provided for @proxyConfigNav.
  ///
  /// In en, this message translates to:
  /// **'Proxy config'**
  String get proxyConfigNav;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @macosProxyHint.
  ///
  /// In en, this message translates to:
  /// **'On macOS: start proxy from proxy config page first'**
  String get macosProxyHint;

  /// No description provided for @goToProxyConfig.
  ///
  /// In en, this message translates to:
  /// **'Go to proxy config'**
  String get goToProxyConfig;

  /// No description provided for @scanQrHint.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code displayed by the proxy service'**
  String get scanQrHint;

  /// No description provided for @runProxyHint.
  ///
  /// In en, this message translates to:
  /// **'Run \"go run . -workdir /path/to/project\" in the proxy folder'**
  String get runProxyHint;

  /// No description provided for @proxyNotStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy not started?'**
  String get proxyNotStartedTitle;

  /// No description provided for @proxyNotStartedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start proxy from proxy config page first, then enter connection details'**
  String get proxyNotStartedSubtitle;

  /// No description provided for @enterConnectionDetails.
  ///
  /// In en, this message translates to:
  /// **'Enter connection details'**
  String get enterConnectionDetails;

  /// No description provided for @findOnComputer.
  ///
  /// In en, this message translates to:
  /// **'Find these on your computer when running the proxy service'**
  String get findOnComputer;

  /// No description provided for @computerIp.
  ///
  /// In en, this message translates to:
  /// **'Computer IP address'**
  String get computerIp;

  /// No description provided for @ipHint.
  ///
  /// In en, this message translates to:
  /// **'192.168.1.100'**
  String get ipHint;

  /// No description provided for @pinHint.
  ///
  /// In en, this message translates to:
  /// **'123456'**
  String get pinHint;

  /// No description provided for @directProxyOverride.
  ///
  /// In en, this message translates to:
  /// **'Direct proxy override'**
  String get directProxyOverride;

  /// No description provided for @directProxyOverrideMessage.
  ///
  /// In en, this message translates to:
  /// **'Bypass pairing and connect directly. (Use only if pairing fails)'**
  String get directProxyOverrideMessage;

  /// No description provided for @connectDirectly.
  ///
  /// In en, this message translates to:
  /// **'Connect directly'**
  String get connectDirectly;

  /// No description provided for @connectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connected, skills and projects synced'**
  String get connectionSuccess;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String connectionFailed(Object error);

  /// No description provided for @manualProxyUrl.
  ///
  /// In en, this message translates to:
  /// **'Manual proxy URL'**
  String get manualProxyUrl;

  /// No description provided for @initializing.
  ///
  /// In en, this message translates to:
  /// **'Initializing...'**
  String get initializing;

  /// No description provided for @checkingConnectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Checking connection...'**
  String get checkingConnectionStatus;

  /// No description provided for @connectingTo.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {ip}...'**
  String connectingTo(Object ip);

  /// No description provided for @tokenExpiredRepairing.
  ///
  /// In en, this message translates to:
  /// **'Token expired, re-pairing...'**
  String get tokenExpiredRepairing;

  /// No description provided for @connectionFailedRepair.
  ///
  /// In en, this message translates to:
  /// **'Connection failed, attempting re-pair...'**
  String get connectionFailedRepair;

  /// No description provided for @connectionFailedPairAgain.
  ///
  /// In en, this message translates to:
  /// **'Connection failed, please pair again'**
  String get connectionFailedPairAgain;

  /// No description provided for @proxyConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy config'**
  String get proxyConfigTitle;

  /// No description provided for @proxyConfigMacOnly.
  ///
  /// In en, this message translates to:
  /// **'Proxy config is macOS only'**
  String get proxyConfigMacOnly;

  /// No description provided for @systemSettings.
  ///
  /// In en, this message translates to:
  /// **'System settings'**
  String get systemSettings;

  /// No description provided for @proxyConnectionInfo.
  ///
  /// In en, this message translates to:
  /// **'Proxy connection (IP / port / PIN)'**
  String get proxyConnectionInfo;

  /// No description provided for @ipLabel.
  ///
  /// In en, this message translates to:
  /// **'IP'**
  String get ipLabel;

  /// No description provided for @portLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get portLabel;

  /// No description provided for @pinOptional.
  ///
  /// In en, this message translates to:
  /// **'PIN (6 digits)'**
  String get pinOptional;

  /// No description provided for @pinOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Fill to auto-pair and connect on start'**
  String get pinOptionalHint;

  /// No description provided for @afterStartUseInfo.
  ///
  /// In en, this message translates to:
  /// **'After start, the above info will be used to connect automatically.'**
  String get afterStartUseInfo;

  /// No description provided for @pleaseStartProxyFirst.
  ///
  /// In en, this message translates to:
  /// **'Please start proxy first'**
  String get pleaseStartProxyFirst;

  /// No description provided for @noSavedConnectionHint.
  ///
  /// In en, this message translates to:
  /// **'No saved connection. Start proxy on this page first, then tap \"Go to pair\" to scan QR.'**
  String get noSavedConnectionHint;

  /// No description provided for @proxyRunning.
  ///
  /// In en, this message translates to:
  /// **'Proxy running'**
  String get proxyRunning;

  /// No description provided for @proxyChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get proxyChecking;

  /// No description provided for @proxyNotRunning.
  ///
  /// In en, this message translates to:
  /// **'Proxy not running'**
  String get proxyNotRunning;

  /// No description provided for @detect.
  ///
  /// In en, this message translates to:
  /// **'Detect'**
  String get detect;

  /// No description provided for @proxyPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Proxy path'**
  String get proxyPathLabel;

  /// No description provided for @proxyPathHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use in-app proxy'**
  String get proxyPathHint;

  /// No description provided for @startProxy.
  ///
  /// In en, this message translates to:
  /// **'Start proxy'**
  String get startProxy;

  /// No description provided for @startingProxy.
  ///
  /// In en, this message translates to:
  /// **'Starting proxy...'**
  String get startingProxy;

  /// No description provided for @startingProxyConnect.
  ///
  /// In en, this message translates to:
  /// **'Starting proxy, connecting...'**
  String get startingProxyConnect;

  /// No description provided for @proxyStartChecking.
  ///
  /// In en, this message translates to:
  /// **'Proxy starting, checking...'**
  String get proxyStartChecking;

  /// No description provided for @startFailed.
  ///
  /// In en, this message translates to:
  /// **'Start failed: {error}'**
  String startFailed(Object error);

  /// No description provided for @proxyStopped.
  ///
  /// In en, this message translates to:
  /// **'Proxy stopped'**
  String get proxyStopped;

  /// No description provided for @stopProxy.
  ///
  /// In en, this message translates to:
  /// **'Stop proxy'**
  String get stopProxy;

  /// No description provided for @stopFailed.
  ///
  /// In en, this message translates to:
  /// **'Stop failed'**
  String get stopFailed;

  /// No description provided for @launchCommand.
  ///
  /// In en, this message translates to:
  /// **'Launch command (for debugging)'**
  String get launchCommand;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @goToPair.
  ///
  /// In en, this message translates to:
  /// **'Go to pair (scan after proxy starts)'**
  String get goToPair;

  /// No description provided for @enterApp.
  ///
  /// In en, this message translates to:
  /// **'Enter app'**
  String get enterApp;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String loadFailed(Object error);

  /// No description provided for @openInCursor.
  ///
  /// In en, this message translates to:
  /// **'Opened in Cursor'**
  String get openInCursor;

  /// No description provided for @cannotOpenCursor.
  ///
  /// In en, this message translates to:
  /// **'Cannot open project, config may be missing'**
  String get cannotOpenCursor;

  /// No description provided for @selectDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select directory'**
  String get selectDirectory;

  /// No description provided for @proxyLaunchParams.
  ///
  /// In en, this message translates to:
  /// **'Proxy launch params'**
  String get proxyLaunchParams;

  /// No description provided for @enableOpenClaw.
  ///
  /// In en, this message translates to:
  /// **'Enable OpenClaw'**
  String get enableOpenClaw;

  /// No description provided for @openClawToken.
  ///
  /// In en, this message translates to:
  /// **'OpenClaw token'**
  String get openClawToken;

  /// No description provided for @openClawUrlOptional.
  ///
  /// In en, this message translates to:
  /// **'OpenClaw URL (optional)'**
  String get openClawUrlOptional;

  /// No description provided for @allowLocalNoAuth.
  ///
  /// In en, this message translates to:
  /// **'Allow local no-auth'**
  String get allowLocalNoAuth;

  /// No description provided for @skillsPath.
  ///
  /// In en, this message translates to:
  /// **'Skills path'**
  String get skillsPath;

  /// No description provided for @workdirOptional.
  ///
  /// In en, this message translates to:
  /// **'Work dir (optional)'**
  String get workdirOptional;

  /// No description provided for @saveLaunchParams.
  ///
  /// In en, this message translates to:
  /// **'Save launch params'**
  String get saveLaunchParams;

  /// No description provided for @launchParamsSaved.
  ///
  /// In en, this message translates to:
  /// **'Launch params saved'**
  String get launchParamsSaved;

  /// No description provided for @noLogPath.
  ///
  /// In en, this message translates to:
  /// **'Log path not set'**
  String get noLogPath;

  /// No description provided for @proxyPathNotSet.
  ///
  /// In en, this message translates to:
  /// **'Proxy path not configured'**
  String get proxyPathNotSet;

  /// No description provided for @logNotGenerated.
  ///
  /// In en, this message translates to:
  /// **'Log file not yet generated: {path}'**
  String logNotGenerated(Object path);

  /// No description provided for @logOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened log with default app'**
  String get logOpened;

  /// No description provided for @viewLog.
  ///
  /// In en, this message translates to:
  /// **'View log'**
  String get viewLog;

  /// No description provided for @proxyStatusNotDetected.
  ///
  /// In en, this message translates to:
  /// **'Proxy status not detected'**
  String get proxyStatusNotDetected;

  /// No description provided for @proxyStartSuccess.
  ///
  /// In en, this message translates to:
  /// **'Proxy running, connecting...'**
  String get proxyStartSuccess;

  /// No description provided for @proxyStartWaitCheck.
  ///
  /// In en, this message translates to:
  /// **'Proxy may still be starting, tap \"Detect\" later'**
  String get proxyStartWaitCheck;

  /// No description provided for @pleasePairFirst.
  ///
  /// In en, this message translates to:
  /// **'Pair or set connection first, then detect/start proxy'**
  String get pleasePairFirst;

  /// No description provided for @loadingConnection.
  ///
  /// In en, this message translates to:
  /// **'Loading connection...'**
  String get loadingConnection;

  /// No description provided for @startProxyPleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Starting proxy, please wait...'**
  String get startProxyPleaseWait;

  /// No description provided for @autoPairedConnected.
  ///
  /// In en, this message translates to:
  /// **'Auto-paired and connected'**
  String get autoPairedConnected;

  /// No description provided for @autoConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto-connect failed, please pair manually'**
  String get autoConnectFailed;

  /// No description provided for @logPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Log path'**
  String get logPathLabel;

  /// No description provided for @logPathHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for default ~/Library/Logs/xassistant-proxy/proxy.log'**
  String get logPathHint;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteTask.
  ///
  /// In en, this message translates to:
  /// **'Delete task'**
  String get deleteTask;

  /// No description provided for @deleteTaskConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"? This cannot be undone.'**
  String deleteTaskConfirmMessage(Object title);

  /// No description provided for @cancelTask.
  ///
  /// In en, this message translates to:
  /// **'Cancel task'**
  String get cancelTask;

  /// No description provided for @submitFeedback.
  ///
  /// In en, this message translates to:
  /// **'Submit feedback'**
  String get submitFeedback;

  /// No description provided for @feedbackSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Feedback submitted'**
  String get feedbackSubmitted;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessage;

  /// No description provided for @deleteMessageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this message?'**
  String get deleteMessageConfirm;

  /// No description provided for @selectTaskProject.
  ///
  /// In en, this message translates to:
  /// **'Select project for task'**
  String get selectTaskProject;

  /// No description provided for @startingCursorAgent.
  ///
  /// In en, this message translates to:
  /// **'Starting Cursor Agent...'**
  String get startingCursorAgent;

  /// No description provided for @startingCcrAgent.
  ///
  /// In en, this message translates to:
  /// **'Starting CCR Agent...'**
  String get startingCcrAgent;

  /// No description provided for @openInCursorLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent Status'**
  String get openInCursorLabel;

  /// No description provided for @planOnly.
  ///
  /// In en, this message translates to:
  /// **'Plan only'**
  String get planOnly;

  /// No description provided for @confirmTaskSkipPlan.
  ///
  /// In en, this message translates to:
  /// **'Confirm task (skip Plan)'**
  String get confirmTaskSkipPlan;

  /// No description provided for @startExecution.
  ///
  /// In en, this message translates to:
  /// **'Start execution'**
  String get startExecution;

  /// No description provided for @submitLabel.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submitLabel;

  /// No description provided for @runTestLabel.
  ///
  /// In en, this message translates to:
  /// **'Run tests'**
  String get runTestLabel;

  /// No description provided for @markComplete.
  ///
  /// In en, this message translates to:
  /// **'Mark complete'**
  String get markComplete;

  /// No description provided for @openingIterm2.
  ///
  /// In en, this message translates to:
  /// **'Opening iTerm2...'**
  String get openingIterm2;

  /// No description provided for @cannotOpenTmux.
  ///
  /// In en, this message translates to:
  /// **'Cannot open tmux, ensure Agent is running'**
  String get cannotOpenTmux;

  /// No description provided for @commandCopied.
  ///
  /// In en, this message translates to:
  /// **'Command copied: {command}'**
  String commandCopied(Object command);

  /// No description provided for @generatingPlan.
  ///
  /// In en, this message translates to:
  /// **'Generating plan...'**
  String get generatingPlan;

  /// No description provided for @generateFailed.
  ///
  /// In en, this message translates to:
  /// **'Generate failed: {error}'**
  String generateFailed(Object error);

  /// No description provided for @executingPhase.
  ///
  /// In en, this message translates to:
  /// **'Executing {phase} phase...'**
  String executingPhase(Object phase);

  /// No description provided for @phaseExecutionFailed.
  ///
  /// In en, this message translates to:
  /// **'Phase execution failed: {error}'**
  String phaseExecutionFailed(Object error);

  /// No description provided for @phaseSwitchFailed.
  ///
  /// In en, this message translates to:
  /// **'Phase switch failed'**
  String get phaseSwitchFailed;

  /// No description provided for @phaseUpdated.
  ///
  /// In en, this message translates to:
  /// **'Phase updated to: {phase}'**
  String phaseUpdated(Object phase);

  /// No description provided for @statusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Status updated to: {status}'**
  String statusUpdated(Object status);

  /// No description provided for @startingAgent.
  ///
  /// In en, this message translates to:
  /// **'Starting {backend} Agent...'**
  String startingAgent(Object backend);

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get codeCopied;

  /// No description provided for @developmentCapabilities.
  ///
  /// In en, this message translates to:
  /// **'Development capabilities'**
  String get developmentCapabilities;

  /// No description provided for @noProjects.
  ///
  /// In en, this message translates to:
  /// **'No projects'**
  String get noProjects;

  /// No description provided for @addProjectToUse.
  ///
  /// In en, this message translates to:
  /// **'Add project to use capabilities'**
  String get addProjectToUse;

  /// No description provided for @requiredInfo.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredInfo;

  /// No description provided for @optionalInfo.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optionalInfo;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(Object error);

  /// No description provided for @notConnectedPleaseConnect.
  ///
  /// In en, this message translates to:
  /// **'Not connected. Please connect in Settings first.'**
  String get notConnectedPleaseConnect;

  /// No description provided for @taskCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Task completed'**
  String get taskCompletedTitle;

  /// No description provided for @taskFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Task failed'**
  String get taskFailedTitle;

  /// No description provided for @taskProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Task progress'**
  String get taskProgressTitle;

  /// No description provided for @taskTitle.
  ///
  /// In en, this message translates to:
  /// **'Task title'**
  String get taskTitle;

  /// No description provided for @taskTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Enter task name...'**
  String get taskTitleHint;

  /// No description provided for @taskTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter task title'**
  String get taskTitleRequired;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @descriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Add task description...'**
  String get descriptionHint;

  /// No description provided for @project.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get project;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @sourceManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get sourceManual;

  /// No description provided for @sourceOpenClaw.
  ///
  /// In en, this message translates to:
  /// **'OpenClaw'**
  String get sourceOpenClaw;

  /// No description provided for @sourceCursor.
  ///
  /// In en, this message translates to:
  /// **'Cursor'**
  String get sourceCursor;

  /// No description provided for @sourceSkill.
  ///
  /// In en, this message translates to:
  /// **'Skill'**
  String get sourceSkill;

  /// No description provided for @agentOptional.
  ///
  /// In en, this message translates to:
  /// **'Execution Agent (optional)'**
  String get agentOptional;

  /// No description provided for @agentCursor.
  ///
  /// In en, this message translates to:
  /// **'Cursor'**
  String get agentCursor;

  /// No description provided for @agentCcr.
  ///
  /// In en, this message translates to:
  /// **'CCR'**
  String get agentCcr;

  /// No description provided for @agentClaude.
  ///
  /// In en, this message translates to:
  /// **'Claude'**
  String get agentClaude;

  /// No description provided for @deadlineOptional.
  ///
  /// In en, this message translates to:
  /// **'Deadline (optional)'**
  String get deadlineOptional;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

  /// No description provided for @selectTime.
  ///
  /// In en, this message translates to:
  /// **'Select time'**
  String get selectTime;

  /// No description provided for @projectKeyManualHint.
  ///
  /// In en, this message translates to:
  /// **'Project key (fill when no projects registered)'**
  String get projectKeyManualHint;

  /// No description provided for @projectKeyExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. xassistant'**
  String get projectKeyExample;

  /// No description provided for @noProjectSelected.
  ///
  /// In en, this message translates to:
  /// **'— None —'**
  String get noProjectSelected;

  /// No description provided for @projectKeyFallbackHint.
  ///
  /// In en, this message translates to:
  /// **'Project key (fill when load failed)'**
  String get projectKeyFallbackHint;

  /// No description provided for @cursorAgentStartedInTmux.
  ///
  /// In en, this message translates to:
  /// **'Cursor Agent started in tmux'**
  String get cursorAgentStartedInTmux;

  /// No description provided for @ccrAgentStartedInTmux.
  ///
  /// In en, this message translates to:
  /// **'CCR Agent started in tmux'**
  String get ccrAgentStartedInTmux;

  /// No description provided for @startFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Start failed'**
  String get startFailedShort;

  /// No description provided for @runWithCursor.
  ///
  /// In en, this message translates to:
  /// **'Run with Cursor'**
  String get runWithCursor;

  /// No description provided for @runWithCcr.
  ///
  /// In en, this message translates to:
  /// **'Run with CCR'**
  String get runWithCcr;

  /// No description provided for @viewAgent.
  ///
  /// In en, this message translates to:
  /// **'View Agent'**
  String get viewAgent;

  /// No description provided for @preferredAgent.
  ///
  /// In en, this message translates to:
  /// **'Preferred Agent'**
  String get preferredAgent;

  /// No description provided for @projectKey.
  ///
  /// In en, this message translates to:
  /// **'Project key'**
  String get projectKey;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created at'**
  String get createdAt;

  /// No description provided for @deadline.
  ///
  /// In en, this message translates to:
  /// **'Deadline'**
  String get deadline;

  /// No description provided for @completedAt.
  ///
  /// In en, this message translates to:
  /// **'Completed at'**
  String get completedAt;

  /// No description provided for @executionPlan.
  ///
  /// In en, this message translates to:
  /// **'Execution plan'**
  String get executionPlan;

  /// No description provided for @planLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load plan (ensure proxy --workdir matches task plan path)'**
  String get planLoadFailed;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @hasIssue.
  ///
  /// In en, this message translates to:
  /// **'Has issue'**
  String get hasIssue;

  /// No description provided for @describeIssue.
  ///
  /// In en, this message translates to:
  /// **'Describe the issue...'**
  String get describeIssue;

  /// No description provided for @addNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Add note (optional)...'**
  String get addNoteOptional;

  /// No description provided for @phasePlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get phasePlan;

  /// No description provided for @phaseCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get phaseCode;

  /// No description provided for @phaseTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get phaseTest;

  /// No description provided for @phaseDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get phaseDone;

  /// No description provided for @statusPhaseFormat.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}{phase}'**
  String statusPhaseFormat(Object status, Object phase);

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// No description provided for @phaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Phase'**
  String get phaseLabel;

  /// No description provided for @changePhase.
  ///
  /// In en, this message translates to:
  /// **'Change phase'**
  String get changePhase;

  /// No description provided for @changeStatus.
  ///
  /// In en, this message translates to:
  /// **'Change status'**
  String get changeStatus;

  /// No description provided for @executionUses.
  ///
  /// In en, this message translates to:
  /// **'This run uses:'**
  String get executionUses;

  /// No description provided for @ccrExecute.
  ///
  /// In en, this message translates to:
  /// **'Run with CCR'**
  String get ccrExecute;

  /// No description provided for @cursorExecute.
  ///
  /// In en, this message translates to:
  /// **'Run with Cursor'**
  String get cursorExecute;

  /// No description provided for @retryCcr.
  ///
  /// In en, this message translates to:
  /// **'Retry CCR'**
  String get retryCcr;

  /// No description provided for @retryCursor.
  ///
  /// In en, this message translates to:
  /// **'Retry Cursor'**
  String get retryCursor;

  /// No description provided for @messageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} messages'**
  String messageCount(Object count);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @todayAt.
  ///
  /// In en, this message translates to:
  /// **'Today {time}'**
  String todayAt(Object time);

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @proxySection.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get proxySection;

  /// No description provided for @proxyStartSuccessSnack.
  ///
  /// In en, this message translates to:
  /// **'Proxy running, connecting...'**
  String get proxyStartSuccessSnack;

  /// No description provided for @proxyStartWaitSnack.
  ///
  /// In en, this message translates to:
  /// **'Proxy may still be starting, tap \"Detect\" later'**
  String get proxyStartWaitSnack;

  /// No description provided for @pleasePairOrConfigThenDetect.
  ///
  /// In en, this message translates to:
  /// **'Pair or set connection first, then detect/start proxy'**
  String get pleasePairOrConfigThenDetect;

  /// No description provided for @proxyStatusNotDetectedShort.
  ///
  /// In en, this message translates to:
  /// **'Status not detected'**
  String get proxyStatusNotDetectedShort;

  /// No description provided for @proxyCheckingShort.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get proxyCheckingShort;

  /// No description provided for @proxyRunningShort.
  ///
  /// In en, this message translates to:
  /// **'Proxy running'**
  String get proxyRunningShort;

  /// No description provided for @proxyNotRunningShort.
  ///
  /// In en, this message translates to:
  /// **'Proxy not running'**
  String get proxyNotRunningShort;

  /// No description provided for @detectFailed.
  ///
  /// In en, this message translates to:
  /// **'Detect failed'**
  String get detectFailed;

  /// No description provided for @detectLabel.
  ///
  /// In en, this message translates to:
  /// **'Detect'**
  String get detectLabel;

  /// No description provided for @launchParamsSavedSnack.
  ///
  /// In en, this message translates to:
  /// **'Launch params saved'**
  String get launchParamsSavedSnack;

  /// No description provided for @proxyPathLabelShort.
  ///
  /// In en, this message translates to:
  /// **'Proxy path'**
  String get proxyPathLabelShort;

  /// No description provided for @proxyPathHintLong.
  ///
  /// In en, this message translates to:
  /// **'/path/to/xassistant-proxy or proxy executable path'**
  String get proxyPathHintLong;

  /// No description provided for @startProxyPleaseWaitSnack.
  ///
  /// In en, this message translates to:
  /// **'Starting proxy, please wait...'**
  String get startProxyPleaseWaitSnack;

  /// No description provided for @startProxyLabel.
  ///
  /// In en, this message translates to:
  /// **'Start proxy'**
  String get startProxyLabel;

  /// No description provided for @loadingConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Loading connection...'**
  String get loadingConnectionTitle;

  /// No description provided for @loadFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String loadFailedWithError(Object error);

  /// No description provided for @proxyLaunchParamsTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy launch params'**
  String get proxyLaunchParamsTitle;

  /// No description provided for @enableOpenClawTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable OpenClaw'**
  String get enableOpenClawTitle;

  /// No description provided for @enableOpenClawSubtitle.
  ///
  /// In en, this message translates to:
  /// **'--openclaw'**
  String get enableOpenClawSubtitle;

  /// No description provided for @openClawTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'OpenClaw Token'**
  String get openClawTokenLabel;

  /// No description provided for @openClawTokenHint.
  ///
  /// In en, this message translates to:
  /// **'--openclaw-token'**
  String get openClawTokenHint;

  /// No description provided for @openClawUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'OpenClaw URL (optional)'**
  String get openClawUrlLabel;

  /// No description provided for @openClawUrlHint.
  ///
  /// In en, this message translates to:
  /// **'--openclaw-url'**
  String get openClawUrlHint;

  /// No description provided for @allowLocalNoAuthTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow local no-auth'**
  String get allowLocalNoAuthTitle;

  /// No description provided for @allowLocalNoAuthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'--allow-local-no-auth (skill calls /api/tasks)'**
  String get allowLocalNoAuthSubtitle;

  /// No description provided for @skillsPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Skills path'**
  String get skillsPathLabel;

  /// No description provided for @skillsPathHint.
  ///
  /// In en, this message translates to:
  /// **'--skills-path, e.g. ../skills'**
  String get skillsPathHint;

  /// No description provided for @selectDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Select directory'**
  String get selectDirectoryLabel;

  /// No description provided for @workdirLabel.
  ///
  /// In en, this message translates to:
  /// **'Work dir (optional)'**
  String get workdirLabel;

  /// No description provided for @workdirHint.
  ///
  /// In en, this message translates to:
  /// **'--workdir'**
  String get workdirHint;

  /// No description provided for @saveLaunchParamsLabel.
  ///
  /// In en, this message translates to:
  /// **'Save launch params'**
  String get saveLaunchParamsLabel;

  /// No description provided for @versionPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'1.0.0'**
  String get versionPlaceholder;

  /// No description provided for @projectCreated.
  ///
  /// In en, this message translates to:
  /// **'Project created'**
  String get projectCreated;

  /// No description provided for @projectUpdated.
  ///
  /// In en, this message translates to:
  /// **'Project updated'**
  String get projectUpdated;

  /// No description provided for @saveFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailedWithError(Object error);

  /// No description provided for @editProject.
  ///
  /// In en, this message translates to:
  /// **'Edit project'**
  String get editProject;

  /// No description provided for @addProject.
  ///
  /// In en, this message translates to:
  /// **'Add project'**
  String get addProject;

  /// No description provided for @requiredInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredInfoTitle;

  /// No description provided for @requiredInfoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Project key, name and path are required'**
  String get requiredInfoSubtitle;

  /// No description provided for @projectKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Project key'**
  String get projectKeyLabel;

  /// No description provided for @projectKeyHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. my_app'**
  String get projectKeyHint;

  /// No description provided for @projectKeyHelper.
  ///
  /// In en, this message translates to:
  /// **'Cannot change after creation, used to identify project'**
  String get projectKeyHelper;

  /// No description provided for @projectNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectNameLabel;

  /// No description provided for @projectNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. My App'**
  String get projectNameHint;

  /// No description provided for @enterProjectKey.
  ///
  /// In en, this message translates to:
  /// **'Please enter project key'**
  String get enterProjectKey;

  /// No description provided for @enterProjectName.
  ///
  /// In en, this message translates to:
  /// **'Please enter project name'**
  String get enterProjectName;

  /// No description provided for @projectPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Project path'**
  String get projectPathLabel;

  /// No description provided for @projectPathHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. /Users/xxx/workspace/my_app'**
  String get projectPathHint;

  /// No description provided for @projectPathHelper.
  ///
  /// In en, this message translates to:
  /// **'Local absolute path to project root'**
  String get projectPathHelper;

  /// No description provided for @enterProjectPath.
  ///
  /// In en, this message translates to:
  /// **'Please enter project path'**
  String get enterProjectPath;

  /// No description provided for @optionalInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optionalInfoTitle;

  /// No description provided for @optionalInfoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type, tech stack, owner, etc.'**
  String get optionalInfoSubtitle;

  /// No description provided for @typeOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Type (optional)'**
  String get typeOptionalLabel;

  /// No description provided for @typeOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. backend-service, tool'**
  String get typeOptionalHint;

  /// No description provided for @techStackLabel.
  ///
  /// In en, this message translates to:
  /// **'Tech stack (optional)'**
  String get techStackLabel;

  /// No description provided for @techStackHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Flutter, Dart, Go (comma separated)'**
  String get techStackHint;

  /// No description provided for @ownerLabel.
  ///
  /// In en, this message translates to:
  /// **'Owner (optional)'**
  String get ownerLabel;

  /// No description provided for @ownerHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. John'**
  String get ownerHint;

  /// No description provided for @statusOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Status (optional)'**
  String get statusOptionalLabel;

  /// No description provided for @statusOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. active, archived'**
  String get statusOptionalHint;

  /// No description provided for @descriptionOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptionalLabel;

  /// No description provided for @descriptionOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Brief project description'**
  String get descriptionOptionalHint;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get createProject;

  /// No description provided for @selectCapabilityToRun.
  ///
  /// In en, this message translates to:
  /// **'Select capability to run'**
  String get selectCapabilityToRun;

  /// No description provided for @registeredProjects.
  ///
  /// In en, this message translates to:
  /// **'Registered projects'**
  String get registeredProjects;

  /// No description provided for @addLabel.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addLabel;

  /// No description provided for @selectExecutor.
  ///
  /// In en, this message translates to:
  /// **'Select executor'**
  String get selectExecutor;

  /// No description provided for @projectLabel.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get projectLabel;

  /// No description provided for @taskTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Task title'**
  String get taskTitleLabel;

  /// No description provided for @taskTitleExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. Optimize inventory sync API'**
  String get taskTitleExample;

  /// No description provided for @requirementLabel.
  ///
  /// In en, this message translates to:
  /// **'Requirement'**
  String get requirementLabel;

  /// No description provided for @requirementHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the feature in detail'**
  String get requirementHint;

  /// No description provided for @cancelLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelLabel;

  /// No description provided for @executeLabel.
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get executeLabel;

  /// No description provided for @pleaseEnterTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Please enter task title'**
  String get pleaseEnterTaskTitle;

  /// No description provided for @notConnectedToProxy.
  ///
  /// In en, this message translates to:
  /// **'Not connected to proxy server'**
  String get notConnectedToProxy;

  /// No description provided for @executing.
  ///
  /// In en, this message translates to:
  /// **'Executing...'**
  String get executing;

  /// No description provided for @taskCreatedSnack.
  ///
  /// In en, this message translates to:
  /// **'Task created: {taskId}'**
  String taskCreatedSnack(Object taskId);

  /// No description provided for @sentToAgentSnack.
  ///
  /// In en, this message translates to:
  /// **'Sent to Agent: {id}'**
  String sentToAgentSnack(Object id);

  /// No description provided for @executeFailedSnack.
  ///
  /// In en, this message translates to:
  /// **'Execute failed: {error}'**
  String executeFailedSnack(Object error);

  /// No description provided for @addProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Add project'**
  String get addProjectTitle;

  /// No description provided for @projectKeyKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Project key'**
  String get projectKeyKeyLabel;

  /// No description provided for @projectKeyKeyHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. my_project'**
  String get projectKeyKeyHint;

  /// No description provided for @projectNameKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectNameKeyLabel;

  /// No description provided for @projectNameKeyHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Inventory system'**
  String get projectNameKeyHint;

  /// No description provided for @projectPathKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Project path'**
  String get projectPathKeyLabel;

  /// No description provided for @projectPathKeyHint.
  ///
  /// In en, this message translates to:
  /// **'/path/to/project'**
  String get projectPathKeyHint;

  /// No description provided for @descriptionKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionKeyLabel;

  /// No description provided for @pleaseFillKeyNamePath.
  ///
  /// In en, this message translates to:
  /// **'Please fill project key, name and path'**
  String get pleaseFillKeyNamePath;

  /// No description provided for @addFailedSnack.
  ///
  /// In en, this message translates to:
  /// **'Add failed: {error}'**
  String addFailedSnack(Object error);

  /// No description provided for @deleteProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete project?'**
  String get deleteProjectTitle;

  /// No description provided for @deleteProjectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete project \"{key}\"?'**
  String deleteProjectConfirm(Object key);

  /// No description provided for @deleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteLabel;

  /// No description provided for @deleteFailedSnack.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailedSnack(Object error);

  /// No description provided for @pleaseAddProjectFirst.
  ///
  /// In en, this message translates to:
  /// **'Please add project first'**
  String get pleaseAddProjectFirst;

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get scheduleTitle;

  /// No description provided for @byDay.
  ///
  /// In en, this message translates to:
  /// **'By day'**
  String get byDay;

  /// No description provided for @weekView.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get weekView;

  /// No description provided for @noScheduleToday.
  ///
  /// In en, this message translates to:
  /// **'No schedule today'**
  String get noScheduleToday;

  /// No description provided for @deleteScheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete schedule'**
  String get deleteScheduleTitle;

  /// No description provided for @deleteScheduleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"?'**
  String deleteScheduleConfirm(Object title);

  /// No description provided for @deleteLabelRed.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteLabelRed;

  /// No description provided for @weekdayShort.
  ///
  /// In en, this message translates to:
  /// **'Sun,Mon,Tue,Wed,Thu,Fri,Sat'**
  String get weekdayShort;

  /// No description provided for @dateFormatFull.
  ///
  /// In en, this message translates to:
  /// **'{weekday}, {month}/{day}'**
  String dateFormatFull(Object weekday, Object month, Object day);

  /// No description provided for @eventTypeMeeting.
  ///
  /// In en, this message translates to:
  /// **'Meeting'**
  String get eventTypeMeeting;

  /// No description provided for @eventTypeDeadline.
  ///
  /// In en, this message translates to:
  /// **'Deadline'**
  String get eventTypeDeadline;

  /// No description provided for @eventTypeSocial.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get eventTypeSocial;

  /// No description provided for @eventTypeReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get eventTypeReview;

  /// No description provided for @eventTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get eventTypeOther;

  /// No description provided for @noItems.
  ///
  /// In en, this message translates to:
  /// **'No items'**
  String get noItems;

  /// No description provided for @editSchedule.
  ///
  /// In en, this message translates to:
  /// **'Edit schedule'**
  String get editSchedule;

  /// No description provided for @newSchedule.
  ///
  /// In en, this message translates to:
  /// **'New schedule'**
  String get newSchedule;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @startTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Start time (YYYY-MM-DDTHH:mm)'**
  String get startTimeLabel;

  /// No description provided for @endTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get endTimeLabel;

  /// No description provided for @descriptionPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Description (location, notes, attendees)'**
  String get descriptionPlaceholder;

  /// No description provided for @projectKeyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Project (projectKey)'**
  String get projectKeyPlaceholder;

  /// No description provided for @createLabel.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createLabel;

  /// No description provided for @projectSkillsTitle.
  ///
  /// In en, this message translates to:
  /// **'Project skills'**
  String get projectSkillsTitle;

  /// No description provided for @developmentCapabilitiesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Development capabilities'**
  String get developmentCapabilitiesTooltip;

  /// No description provided for @allSkillsTooltip.
  ///
  /// In en, this message translates to:
  /// **'All skills'**
  String get allSkillsTooltip;

  /// No description provided for @noSkillsYet.
  ///
  /// In en, this message translates to:
  /// **'No skills yet'**
  String get noSkillsYet;

  /// No description provided for @addSkillPathInSettings.
  ///
  /// In en, this message translates to:
  /// **'Add skill path in Settings'**
  String get addSkillPathInSettings;

  /// No description provided for @skillsLabel.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skillsLabel;

  /// No description provided for @retryLabel.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryLabel;

  /// No description provided for @loadFailedWithColon.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String loadFailedWithColon(Object error);

  /// No description provided for @addFirstProject.
  ///
  /// In en, this message translates to:
  /// **'Add first project'**
  String get addFirstProject;

  /// No description provided for @editTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editTooltip;

  /// No description provided for @deleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteTooltip;

  /// No description provided for @loadProjectsFailed.
  ///
  /// In en, this message translates to:
  /// **'Load projects failed: {error}'**
  String loadProjectsFailed(Object error);

  /// No description provided for @deleteProjectTitleShort.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProjectTitleShort;

  /// No description provided for @deleteProjectConfirmName.
  ///
  /// In en, this message translates to:
  /// **'Delete project \"{name}\"?'**
  String deleteProjectConfirmName(Object name);

  /// No description provided for @projectDeletedSnack.
  ///
  /// In en, this message translates to:
  /// **'Project deleted: {name}'**
  String projectDeletedSnack(Object name);

  /// No description provided for @useLabel.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get useLabel;

  /// No description provided for @notConnectedToProxyShort.
  ///
  /// In en, this message translates to:
  /// **'Not connected to Proxy'**
  String get notConnectedToProxyShort;

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error: '**
  String get errorPrefix;

  /// No description provided for @manageProjectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Projects'**
  String get manageProjectsTitle;

  /// No description provided for @noProjectsFound.
  ///
  /// In en, this message translates to:
  /// **'No projects found.'**
  String get noProjectsFound;

  /// No description provided for @errorColon.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorColon(Object error);

  /// No description provided for @deleteProjectConfirmFull.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\" (Key: {key})?'**
  String deleteProjectConfirmFull(Object name, Object key);

  /// No description provided for @cancelLabelCap.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelLabelCap;

  /// No description provided for @projectDeletedSnackFull.
  ///
  /// In en, this message translates to:
  /// **'Project deleted: {name}'**
  String projectDeletedSnackFull(Object name);

  /// No description provided for @deleteFailedSnackFull.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete project: {error}'**
  String deleteFailedSnackFull(Object error);

  /// No description provided for @deleteLabelCap.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteLabelCap;

  /// No description provided for @skillsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skillsScreenTitle;

  /// No description provided for @noSkillsYetShort.
  ///
  /// In en, this message translates to:
  /// **'No skills yet'**
  String get noSkillsYetShort;

  /// No description provided for @addSkillPathInSettingsShort.
  ///
  /// In en, this message translates to:
  /// **'Add skill path in Settings'**
  String get addSkillPathInSettingsShort;

  /// No description provided for @copiedToClipboardShort.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboardShort;

  /// No description provided for @codeCopiedShort.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get codeCopiedShort;

  /// No description provided for @ipPortHint.
  ///
  /// In en, this message translates to:
  /// **'127.0.0.1'**
  String get ipPortHint;

  /// No description provided for @portHintShort.
  ///
  /// In en, this message translates to:
  /// **'8443'**
  String get portHintShort;

  /// No description provided for @pinDash.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get pinDash;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String minutesAgo(Object count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hr ago'**
  String hoursAgo(Object count);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String daysAgo(Object count);

  /// No description provided for @daysLater.
  ///
  /// In en, this message translates to:
  /// **'In {count} days'**
  String daysLater(Object count);

  /// No description provided for @taskStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get taskStatusPending;

  /// No description provided for @taskStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get taskStatusConfirmed;

  /// No description provided for @taskStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get taskStatusInProgress;

  /// No description provided for @taskStatusPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get taskStatusPlanned;

  /// No description provided for @taskStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get taskStatusCompleted;

  /// No description provided for @taskStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get taskStatusCancelled;

  /// No description provided for @taskStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get taskStatusFailed;

  /// No description provided for @taskStatusPlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning'**
  String get taskStatusPlanning;

  /// No description provided for @taskStatusCoding.
  ///
  /// In en, this message translates to:
  /// **'Coding'**
  String get taskStatusCoding;

  /// No description provided for @taskStatusTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing'**
  String get taskStatusTesting;

  /// No description provided for @taskStatusSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting'**
  String get taskStatusSubmitting;

  /// No description provided for @taskPriorityP0.
  ///
  /// In en, this message translates to:
  /// **'P0 Critical'**
  String get taskPriorityP0;

  /// No description provided for @taskPriorityP1.
  ///
  /// In en, this message translates to:
  /// **'P1 High'**
  String get taskPriorityP1;

  /// No description provided for @taskPriorityP2.
  ///
  /// In en, this message translates to:
  /// **'P2 Medium'**
  String get taskPriorityP2;

  /// No description provided for @taskPriorityP3.
  ///
  /// In en, this message translates to:
  /// **'P3 Low'**
  String get taskPriorityP3;

  /// No description provided for @feedbackTypeDone.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get feedbackTypeDone;

  /// No description provided for @feedbackTypeHasIssue.
  ///
  /// In en, this message translates to:
  /// **'Has Issue'**
  String get feedbackTypeHasIssue;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @untitledConversation.
  ///
  /// In en, this message translates to:
  /// **'Untitled conversation'**
  String get untitledConversation;

  /// No description provided for @scheduleStatusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get scheduleStatusScheduled;

  /// No description provided for @scheduleStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get scheduleStatusInProgress;

  /// No description provided for @scheduleStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get scheduleStatusCompleted;

  /// No description provided for @scheduleStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get scheduleStatusCancelled;

  /// No description provided for @scheduleStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get scheduleStatusLabel;

  /// No description provided for @changeScheduleStatus.
  ///
  /// In en, this message translates to:
  /// **'Change Status'**
  String get changeScheduleStatus;

  /// No description provided for @scheduleStatusChangeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Status updated to \"{status}\"'**
  String scheduleStatusChangeSuccess(String status);

  /// No description provided for @scheduleStatusChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update status'**
  String get scheduleStatusChangeFailed;

  /// No description provided for @scheduleDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule detail'**
  String get scheduleDetailTitle;

  /// No description provided for @linkedTasks.
  ///
  /// In en, this message translates to:
  /// **'Linked tasks'**
  String get linkedTasks;

  /// No description provided for @noLinkedTasks.
  ///
  /// In en, this message translates to:
  /// **'No linked tasks'**
  String get noLinkedTasks;
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
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
