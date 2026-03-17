// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'XAssistant';

  @override
  String get appSubtitle => 'AI Assistant for xassistant';

  @override
  String get navHome => 'Home';

  @override
  String get navTasks => 'Tasks';

  @override
  String get navSchedule => 'Schedule';

  @override
  String get navMessages => 'Messages';

  @override
  String get navSettings => 'Settings';

  @override
  String get settings => 'Settings';

  @override
  String get connection => 'Connection';

  @override
  String get pairNewDevice => 'Pair New Device';

  @override
  String get setManualProxy => 'Set Manual Proxy';

  @override
  String get bypassPairingHint => 'Bypass pairing to connect directly';

  @override
  String get connectedDevice => 'Connected Device';

  @override
  String deviceInfo(Object deviceName, Object ip, Object port) {
    return '$deviceName ($ip:$port)';
  }

  @override
  String get disconnect => 'Disconnect';

  @override
  String get connectionMayHaveIssue => 'Connection may have an issue';

  @override
  String get diagnose => 'Diagnose';

  @override
  String get connectionDiagnosis => 'Connection diagnosis';

  @override
  String get checkingConnection => 'Checking connection...';

  @override
  String get errorLoadingConnection => 'Error loading connection';

  @override
  String get proxyConfig => 'Proxy config';

  @override
  String get proxyConfigSubtitle =>
      'Start, stop proxy and manage launch params';

  @override
  String get openclawSkills => 'OpenClaw skills';

  @override
  String get addSkillPath => 'Add skill path';

  @override
  String get cannotLoadSkillPaths => 'Cannot load skill paths';

  @override
  String get xAssistantProjects => 'XAssistant / Projects';

  @override
  String get manageProjects => 'Manage projects';

  @override
  String get projectsSubtitle => 'View, add and edit projects';

  @override
  String projectsCount(Object count) {
    return '$count projects';
  }

  @override
  String get loading => 'Loading...';

  @override
  String get voice => 'Voice';

  @override
  String get textToSpeech => 'Text-to-Speech';

  @override
  String get readAloud => 'Read responses aloud';

  @override
  String get speechRate => 'Speech rate';

  @override
  String get normal => 'Normal';

  @override
  String get notifications => 'Notifications';

  @override
  String get systemNotification => 'System notification';

  @override
  String get systemNotificationSubtitle => 'Push when task completes';

  @override
  String get viewMessages => 'View messages';

  @override
  String get viewNotificationHistory => 'View in-app notification history';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get system => 'System';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get github => 'GitHub';

  @override
  String get cancel => 'Cancel';

  @override
  String get add => 'Add';

  @override
  String get path => 'Path';

  @override
  String get pathHint => '/path/to/skills or ~/skills';

  @override
  String get disconnectConfirmTitle => 'Disconnect';

  @override
  String get disconnectConfirmMessage =>
      'Are you sure you want to disconnect from this computer?';

  @override
  String get resetPinTitle => 'Reset PIN';

  @override
  String get resetPinMessage =>
      'Reset will invalidate the old PIN. You need to re-pair with the new PIN.';

  @override
  String currentPin(Object pin) {
    return 'Current PIN: $pin';
  }

  @override
  String get confirmReset => 'Confirm reset';

  @override
  String pinResetSuccess(Object pin) {
    return 'PIN reset to: $pin';
  }

  @override
  String resetFailed(Object error) {
    return 'Reset failed: $error';
  }

  @override
  String get editConnection => 'Edit connection';

  @override
  String get ipAddress => 'IP address';

  @override
  String get port => 'Port';

  @override
  String get pinCode => 'PIN code';

  @override
  String get pinUseSavedHint => 'Use saved PIN (or enter new)';

  @override
  String get pinEnterHint => 'Enter PIN';

  @override
  String get leaveEmptyUseSavedPin => 'Leave empty to use saved PIN';

  @override
  String get connect => 'Connect';

  @override
  String pairFailed(Object error) {
    return 'Failed to pair: $error';
  }

  @override
  String get pleaseFillAllFields => 'Please fill all fields';

  @override
  String get diagnosisCurrentState => 'Current state';

  @override
  String get diagnosisSavedIp => 'Saved IP';

  @override
  String get diagnosisFailCount => 'Consecutive failures';

  @override
  String diagnosisFailCountValue(Object count) {
    return '$count times';
  }

  @override
  String get close => 'Close';

  @override
  String get rePair => 'Re-pair';

  @override
  String get refresh => 'Refresh';

  @override
  String get stateUnknown => 'Unknown';

  @override
  String get stateConnected => 'Connected';

  @override
  String get stateConnecting => 'Connecting...';

  @override
  String get stateNetworkError => 'Network error';

  @override
  String get stateIpChanged => 'IP may have changed';

  @override
  String get stateAuthError => 'Auth error';

  @override
  String pinCodeReusable(Object pin) {
    return 'PIN: $pin (reusable)';
  }

  @override
  String get resetPinTooltip => 'Reset PIN';

  @override
  String get language => 'Language';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get taskList => 'Task list';

  @override
  String get taskDetail => 'Task detail';

  @override
  String get taskNotFound => 'Task not found';

  @override
  String get addTask => 'Add task';

  @override
  String get editTask => 'Edit task';

  @override
  String get save => 'Save';

  @override
  String get filterAll => 'All';

  @override
  String get filterPending => 'Pending';

  @override
  String get filterInProgress => 'In progress';

  @override
  String get filterCompleted => 'Completed';

  @override
  String get emptyTasksAll => 'No tasks';

  @override
  String get emptyTasksPending => 'No pending tasks';

  @override
  String get emptyTasksInProgress => 'No in-progress tasks';

  @override
  String get emptyTasksCompleted => 'No completed tasks yet';

  @override
  String get dashboardInProgress => 'In progress';

  @override
  String get dashboardPending => 'Pending';

  @override
  String get greetingNight => 'Late night 🌙';

  @override
  String get greetingMorning => 'Good morning ☀️';

  @override
  String get greetingNoon => 'Good noon 🌤';

  @override
  String get greetingAfternoon => 'Good afternoon ⛅';

  @override
  String get greetingEvening => 'Good evening 🌙';

  @override
  String get scheduleArrow => 'Schedule →';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get typeCommand => 'Type a command...';

  @override
  String get cancelTooltip => 'Cancel';

  @override
  String get historyTooltip => 'History';

  @override
  String get notConnectedToServer => 'Not connected to server';

  @override
  String get waitForConversation =>
      'Please wait for the current conversation to finish';

  @override
  String get fixErrors => 'Fix errors';

  @override
  String get runTests => 'Run tests';

  @override
  String get explainCode => 'Explain code';

  @override
  String get quickResponse => 'Quick response';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get retry => 'Retry';

  @override
  String get connectionError =>
      'Connection error. Please check your connection.';

  @override
  String get disconnectedFromServer => 'Disconnected from server.';

  @override
  String get reconnect => 'Reconnect';

  @override
  String agentBackendError(Object error) {
    return 'Agent backend: $error';
  }

  @override
  String get agentBackendDisconnected =>
      'Agent backend disconnected. Replies may be delayed.';

  @override
  String get fixErrorsCommand => 'Fix any errors in the current file';

  @override
  String get runTestsCommand => 'Run the tests';

  @override
  String get explainCodeCommand => 'Explain this code';

  @override
  String get commandHistory => 'Command history';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get clearHistoryConfirm =>
      'Clear all command history? This cannot be undone.';

  @override
  String get noCommandHistory => 'No command history yet';

  @override
  String get messages => 'Messages';

  @override
  String get noNotifications => 'No messages yet';

  @override
  String get notificationsHint =>
      'You will get notifications here when tasks complete';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get markAllReadConfirm => 'Mark all messages as read?';

  @override
  String get clearMessages => 'Clear messages';

  @override
  String get clearMessagesConfirm =>
      'Clear all messages? This cannot be undone.';

  @override
  String get confirm => 'Confirm';

  @override
  String get clear => 'Clear';

  @override
  String get connectToComputer => 'Connect to computer';

  @override
  String get startProxyFirst => 'Start/configure proxy first';

  @override
  String get proxyConfigNav => 'Proxy config';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get manual => 'Manual';

  @override
  String get connecting => 'Connecting...';

  @override
  String get macosProxyHint =>
      'On macOS: start proxy from proxy config page first';

  @override
  String get goToProxyConfig => 'Go to proxy config';

  @override
  String get scanQrHint => 'Scan the QR code displayed by the proxy service';

  @override
  String get runProxyHint =>
      'Run \"go run . -workdir /path/to/project\" in the proxy folder';

  @override
  String get proxyNotStartedTitle => 'Proxy not started?';

  @override
  String get proxyNotStartedSubtitle =>
      'Start proxy from proxy config page first, then enter connection details';

  @override
  String get enterConnectionDetails => 'Enter connection details';

  @override
  String get findOnComputer =>
      'Find these on your computer when running the proxy service';

  @override
  String get computerIp => 'Computer IP address';

  @override
  String get ipHint => '192.168.1.100';

  @override
  String get pinHint => '123456';

  @override
  String get directProxyOverride => 'Direct proxy override';

  @override
  String get directProxyOverrideMessage =>
      'Bypass pairing and connect directly. (Use only if pairing fails)';

  @override
  String get connectDirectly => 'Connect directly';

  @override
  String get connectionSuccess => 'Connected, skills and projects synced';

  @override
  String connectionFailed(Object error) {
    return 'Connection failed: $error';
  }

  @override
  String get manualProxyUrl => 'Manual proxy URL';

  @override
  String get initializing => 'Initializing...';

  @override
  String get checkingConnectionStatus => 'Checking connection...';

  @override
  String connectingTo(Object ip) {
    return 'Connecting to $ip...';
  }

  @override
  String get tokenExpiredRepairing => 'Token expired, re-pairing...';

  @override
  String get connectionFailedRepair =>
      'Connection failed, attempting re-pair...';

  @override
  String get connectionFailedPairAgain =>
      'Connection failed, please pair again';

  @override
  String get proxyConfigTitle => 'Proxy config';

  @override
  String get proxyConfigMacOnly => 'Proxy config is macOS only';

  @override
  String get systemSettings => 'System settings';

  @override
  String get proxyConnectionInfo => 'Proxy connection (IP / port / PIN)';

  @override
  String get ipLabel => 'IP';

  @override
  String get portLabel => 'Port';

  @override
  String get pinOptional => 'PIN (6 digits)';

  @override
  String get pinOptionalHint => 'Fill to auto-pair and connect on start';

  @override
  String get afterStartUseInfo =>
      'After start, the above info will be used to connect automatically.';

  @override
  String get pleaseStartProxyFirst => 'Please start proxy first';

  @override
  String get noSavedConnectionHint =>
      'No saved connection. Start proxy on this page first, then tap \"Go to pair\" to scan QR.';

  @override
  String get proxyRunning => 'Proxy running';

  @override
  String get proxyChecking => 'Checking...';

  @override
  String get proxyNotRunning => 'Proxy not running';

  @override
  String get detect => 'Detect';

  @override
  String get proxyPathLabel => 'Proxy path';

  @override
  String get proxyPathHint => 'Leave empty to use in-app proxy';

  @override
  String get startProxy => 'Start proxy';

  @override
  String get startingProxy => 'Starting proxy...';

  @override
  String get startingProxyConnect => 'Starting proxy, connecting...';

  @override
  String get proxyStartChecking => 'Proxy starting, checking...';

  @override
  String startFailed(Object error) {
    return 'Start failed: $error';
  }

  @override
  String get proxyStopped => 'Proxy stopped';

  @override
  String get stopProxy => 'Stop proxy';

  @override
  String get stopFailed => 'Stop failed';

  @override
  String get launchCommand => 'Launch command (for debugging)';

  @override
  String get copy => 'Copy';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get goToPair => 'Go to pair (scan after proxy starts)';

  @override
  String get enterApp => 'Enter app';

  @override
  String loadFailed(Object error) {
    return 'Load failed: $error';
  }

  @override
  String get openInCursor => 'Opened in Cursor';

  @override
  String get cannotOpenCursor => 'Cannot open project, config may be missing';

  @override
  String get selectDirectory => 'Select directory';

  @override
  String get proxyLaunchParams => 'Proxy launch params';

  @override
  String get enableOpenClaw => 'Enable OpenClaw';

  @override
  String get openClawToken => 'OpenClaw token';

  @override
  String get openClawUrlOptional => 'OpenClaw URL (optional)';

  @override
  String get allowLocalNoAuth => 'Allow local no-auth';

  @override
  String get skillsPath => 'Skills path';

  @override
  String get workdirOptional => 'Work dir (optional)';

  @override
  String get saveLaunchParams => 'Save launch params';

  @override
  String get launchParamsSaved => 'Launch params saved';

  @override
  String get noLogPath => 'Log path not set';

  @override
  String get proxyPathNotSet => 'Proxy path not configured';

  @override
  String logNotGenerated(Object path) {
    return 'Log file not yet generated: $path';
  }

  @override
  String get logOpened => 'Opened log with default app';

  @override
  String get viewLog => 'View log';

  @override
  String get proxyStatusNotDetected => 'Proxy status not detected';

  @override
  String get proxyStartSuccess => 'Proxy running, connecting...';

  @override
  String get proxyStartWaitCheck =>
      'Proxy may still be starting, tap \"Detect\" later';

  @override
  String get pleasePairFirst =>
      'Pair or set connection first, then detect/start proxy';

  @override
  String get loadingConnection => 'Loading connection...';

  @override
  String get startProxyPleaseWait => 'Starting proxy, please wait...';

  @override
  String get autoPairedConnected => 'Auto-paired and connected';

  @override
  String get autoConnectFailed => 'Auto-connect failed, please pair manually';

  @override
  String get logPathLabel => 'Log path';

  @override
  String get logPathHint =>
      'Leave empty for default ~/Library/Logs/xassistant-proxy/proxy.log';

  @override
  String get delete => 'Delete';

  @override
  String get deleteTask => 'Delete task';

  @override
  String deleteTaskConfirmMessage(Object title) {
    return 'Delete \"$title\"? This cannot be undone.';
  }

  @override
  String get cancelTask => 'Cancel task';

  @override
  String get submitFeedback => 'Submit feedback';

  @override
  String get feedbackSubmitted => 'Feedback submitted';

  @override
  String get deleteMessage => 'Delete message';

  @override
  String get deleteMessageConfirm => 'Delete this message?';

  @override
  String get selectTaskProject => 'Select project for task';

  @override
  String get startingCursorAgent => 'Starting Cursor Agent...';

  @override
  String get startingCcrAgent => 'Starting CCR Agent...';

  @override
  String get openInCursorLabel => 'Agent Status';

  @override
  String get planOnly => 'Plan only';

  @override
  String get confirmTaskSkipPlan => 'Confirm task (skip Plan)';

  @override
  String get startExecution => 'Start execution';

  @override
  String get submitLabel => 'Submit';

  @override
  String get runTestLabel => 'Run tests';

  @override
  String get markComplete => 'Mark complete';

  @override
  String get openingIterm2 => 'Opening iTerm2...';

  @override
  String get cannotOpenTmux => 'Cannot open tmux, ensure Agent is running';

  @override
  String commandCopied(Object command) {
    return 'Command copied: $command';
  }

  @override
  String get generatingPlan => 'Generating plan...';

  @override
  String generateFailed(Object error) {
    return 'Generate failed: $error';
  }

  @override
  String executingPhase(Object phase) {
    return 'Executing $phase phase...';
  }

  @override
  String phaseExecutionFailed(Object error) {
    return 'Phase execution failed: $error';
  }

  @override
  String get phaseSwitchFailed => 'Phase switch failed';

  @override
  String phaseUpdated(Object phase) {
    return 'Phase updated to: $phase';
  }

  @override
  String statusUpdated(Object status) {
    return 'Status updated to: $status';
  }

  @override
  String startingAgent(Object backend) {
    return 'Starting $backend Agent...';
  }

  @override
  String get codeCopied => 'Code copied';

  @override
  String get developmentCapabilities => 'Development capabilities';

  @override
  String get noProjects => 'No projects';

  @override
  String get addProjectToUse => 'Add project to use capabilities';

  @override
  String get requiredInfo => 'Required';

  @override
  String get optionalInfo => 'Optional';

  @override
  String saveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get notConnectedPleaseConnect =>
      'Not connected. Please connect in Settings first.';

  @override
  String get taskCompletedTitle => 'Task completed';

  @override
  String get taskFailedTitle => 'Task failed';

  @override
  String get taskProgressTitle => 'Task progress';

  @override
  String get taskTitle => 'Task title';

  @override
  String get taskTitleHint => 'Enter task name...';

  @override
  String get taskTitleRequired => 'Please enter task title';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get descriptionHint => 'Add task description...';

  @override
  String get project => 'Project';

  @override
  String get priority => 'Priority';

  @override
  String get source => 'Source';

  @override
  String get sourceManual => 'Manual';

  @override
  String get sourceOpenClaw => 'OpenClaw';

  @override
  String get sourceCursor => 'Cursor';

  @override
  String get sourceSkill => 'Skill';

  @override
  String get agentOptional => 'Execution Agent (optional)';

  @override
  String get agentCursor => 'Cursor';

  @override
  String get agentCcr => 'CCR';

  @override
  String get agentClaude => 'Claude';

  @override
  String get deadlineOptional => 'Deadline (optional)';

  @override
  String get selectDate => 'Select date';

  @override
  String get selectTime => 'Select time';

  @override
  String get projectKeyManualHint =>
      'Project key (fill when no projects registered)';

  @override
  String get projectKeyExample => 'e.g. xassistant';

  @override
  String get noProjectSelected => '— None —';

  @override
  String get projectKeyFallbackHint => 'Project key (fill when load failed)';

  @override
  String get cursorAgentStartedInTmux => 'Cursor Agent started in tmux';

  @override
  String get ccrAgentStartedInTmux => 'CCR Agent started in tmux';

  @override
  String get startFailedShort => 'Start failed';

  @override
  String get runWithCursor => 'Run with Cursor';

  @override
  String get runWithCcr => 'Run with CCR';

  @override
  String get viewAgent => 'View Agent';

  @override
  String get preferredAgent => 'Preferred Agent';

  @override
  String get projectKey => 'Project key';

  @override
  String get createdAt => 'Created at';

  @override
  String get deadline => 'Deadline';

  @override
  String get completedAt => 'Completed at';

  @override
  String get executionPlan => 'Execution plan';

  @override
  String get planLoadFailed =>
      'Failed to load plan (ensure proxy --workdir matches task plan path)';

  @override
  String get description => 'Description';

  @override
  String get feedback => 'Feedback';

  @override
  String get completed => 'Completed';

  @override
  String get hasIssue => 'Has issue';

  @override
  String get describeIssue => 'Describe the issue...';

  @override
  String get addNoteOptional => 'Add note (optional)...';

  @override
  String get phasePlan => 'Plan';

  @override
  String get phaseCode => 'Code';

  @override
  String get phaseTest => 'Test';

  @override
  String get phaseDone => 'Done';

  @override
  String statusPhaseFormat(Object status, Object phase) {
    return 'Status: $status$phase';
  }

  @override
  String get statusLabel => 'Status';

  @override
  String get phaseLabel => 'Phase';

  @override
  String get changePhase => 'Change phase';

  @override
  String get changeStatus => 'Change status';

  @override
  String get executionUses => 'This run uses:';

  @override
  String get ccrExecute => 'Run with CCR';

  @override
  String get cursorExecute => 'Run with Cursor';

  @override
  String get retryCcr => 'Retry CCR';

  @override
  String get retryCursor => 'Retry Cursor';

  @override
  String messageCount(Object count) {
    return '$count messages';
  }

  @override
  String get justNow => 'Just now';

  @override
  String todayAt(Object time) {
    return 'Today $time';
  }

  @override
  String get tomorrow => 'Tomorrow';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get proxySection => 'Proxy';

  @override
  String get proxyStartSuccessSnack => 'Proxy running, connecting...';

  @override
  String get proxyStartWaitSnack =>
      'Proxy may still be starting, tap \"Detect\" later';

  @override
  String get pleasePairOrConfigThenDetect =>
      'Pair or set connection first, then detect/start proxy';

  @override
  String get proxyStatusNotDetectedShort => 'Status not detected';

  @override
  String get proxyCheckingShort => 'Checking...';

  @override
  String get proxyRunningShort => 'Proxy running';

  @override
  String get proxyNotRunningShort => 'Proxy not running';

  @override
  String get detectFailed => 'Detect failed';

  @override
  String get detectLabel => 'Detect';

  @override
  String get launchParamsSavedSnack => 'Launch params saved';

  @override
  String get proxyPathLabelShort => 'Proxy path';

  @override
  String get proxyPathHintLong =>
      '/path/to/xassistant-proxy or proxy executable path';

  @override
  String get startProxyPleaseWaitSnack => 'Starting proxy, please wait...';

  @override
  String get startProxyLabel => 'Start proxy';

  @override
  String get loadingConnectionTitle => 'Loading connection...';

  @override
  String loadFailedWithError(Object error) {
    return 'Load failed: $error';
  }

  @override
  String get proxyLaunchParamsTitle => 'Proxy launch params';

  @override
  String get enableOpenClawTitle => 'Enable OpenClaw';

  @override
  String get enableOpenClawSubtitle => '--openclaw';

  @override
  String get openClawTokenLabel => 'OpenClaw Token';

  @override
  String get openClawTokenHint => '--openclaw-token';

  @override
  String get openClawUrlLabel => 'OpenClaw URL (optional)';

  @override
  String get openClawUrlHint => '--openclaw-url';

  @override
  String get allowLocalNoAuthTitle => 'Allow local no-auth';

  @override
  String get allowLocalNoAuthSubtitle =>
      '--allow-local-no-auth (skill calls /api/tasks)';

  @override
  String get skillsPathLabel => 'Skills path';

  @override
  String get skillsPathHint => '--skills-path, e.g. ../skills';

  @override
  String get selectDirectoryLabel => 'Select directory';

  @override
  String get workdirLabel => 'Work dir (optional)';

  @override
  String get workdirHint => '--workdir';

  @override
  String get saveLaunchParamsLabel => 'Save launch params';

  @override
  String get versionPlaceholder => '1.0.0';

  @override
  String get projectCreated => 'Project created';

  @override
  String get projectUpdated => 'Project updated';

  @override
  String saveFailedWithError(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get editProject => 'Edit project';

  @override
  String get addProject => 'Add project';

  @override
  String get requiredInfoTitle => 'Required';

  @override
  String get requiredInfoSubtitle => 'Project key, name and path are required';

  @override
  String get projectKeyLabel => 'Project key';

  @override
  String get projectKeyHint => 'e.g. my_app';

  @override
  String get projectKeyHelper =>
      'Cannot change after creation, used to identify project';

  @override
  String get projectNameLabel => 'Project name';

  @override
  String get projectNameHint => 'e.g. My App';

  @override
  String get enterProjectKey => 'Please enter project key';

  @override
  String get enterProjectName => 'Please enter project name';

  @override
  String get projectPathLabel => 'Project path';

  @override
  String get projectPathHint => 'e.g. /Users/xxx/workspace/my_app';

  @override
  String get projectPathHelper => 'Local absolute path to project root';

  @override
  String get enterProjectPath => 'Please enter project path';

  @override
  String get optionalInfoTitle => 'Optional';

  @override
  String get optionalInfoSubtitle => 'Type, tech stack, owner, etc.';

  @override
  String get typeOptionalLabel => 'Type (optional)';

  @override
  String get typeOptionalHint => 'e.g. backend-service, tool';

  @override
  String get techStackLabel => 'Tech stack (optional)';

  @override
  String get techStackHint => 'e.g. Flutter, Dart, Go (comma separated)';

  @override
  String get ownerLabel => 'Owner (optional)';

  @override
  String get ownerHint => 'e.g. John';

  @override
  String get statusOptionalLabel => 'Status (optional)';

  @override
  String get statusOptionalHint => 'e.g. active, archived';

  @override
  String get descriptionOptionalLabel => 'Description (optional)';

  @override
  String get descriptionOptionalHint => 'Brief project description';

  @override
  String get saving => 'Saving…';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get createProject => 'Create project';

  @override
  String get selectCapabilityToRun => 'Select capability to run';

  @override
  String get registeredProjects => 'Registered projects';

  @override
  String get addLabel => 'Add';

  @override
  String get selectExecutor => 'Select executor';

  @override
  String get projectLabel => 'Project';

  @override
  String get taskTitleLabel => 'Task title';

  @override
  String get taskTitleExample => 'e.g. Optimize inventory sync API';

  @override
  String get requirementLabel => 'Requirement';

  @override
  String get requirementHint => 'Describe the feature in detail';

  @override
  String get cancelLabel => 'Cancel';

  @override
  String get executeLabel => 'Execute';

  @override
  String get pleaseEnterTaskTitle => 'Please enter task title';

  @override
  String get notConnectedToProxy => 'Not connected to proxy server';

  @override
  String get executing => 'Executing...';

  @override
  String taskCreatedSnack(Object taskId) {
    return 'Task created: $taskId';
  }

  @override
  String sentToAgentSnack(Object id) {
    return 'Sent to Agent: $id';
  }

  @override
  String executeFailedSnack(Object error) {
    return 'Execute failed: $error';
  }

  @override
  String get addProjectTitle => 'Add project';

  @override
  String get projectKeyKeyLabel => 'Project key';

  @override
  String get projectKeyKeyHint => 'e.g. my_project';

  @override
  String get projectNameKeyLabel => 'Project name';

  @override
  String get projectNameKeyHint => 'e.g. Inventory system';

  @override
  String get projectPathKeyLabel => 'Project path';

  @override
  String get projectPathKeyHint => '/path/to/project';

  @override
  String get descriptionKeyLabel => 'Description (optional)';

  @override
  String get pleaseFillKeyNamePath => 'Please fill project key, name and path';

  @override
  String addFailedSnack(Object error) {
    return 'Add failed: $error';
  }

  @override
  String get deleteProjectTitle => 'Delete project?';

  @override
  String deleteProjectConfirm(Object key) {
    return 'Delete project \"$key\"?';
  }

  @override
  String get deleteLabel => 'Delete';

  @override
  String deleteFailedSnack(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String get pleaseAddProjectFirst => 'Please add project first';

  @override
  String get scheduleTitle => 'Schedule';

  @override
  String get byDay => 'By day';

  @override
  String get weekView => 'Week';

  @override
  String get noScheduleToday => 'No schedule today';

  @override
  String get deleteScheduleTitle => 'Delete schedule';

  @override
  String deleteScheduleConfirm(Object title) {
    return 'Delete \"$title\"?';
  }

  @override
  String get deleteLabelRed => 'Delete';

  @override
  String get weekdayShort => 'Sun,Mon,Tue,Wed,Thu,Fri,Sat';

  @override
  String dateFormatFull(Object weekday, Object month, Object day) {
    return '$weekday, $month/$day';
  }

  @override
  String get eventTypeMeeting => 'Meeting';

  @override
  String get eventTypeDeadline => 'Deadline';

  @override
  String get eventTypeSocial => 'Social';

  @override
  String get eventTypeReview => 'Review';

  @override
  String get eventTypeOther => 'Other';

  @override
  String get noItems => 'No items';

  @override
  String get editSchedule => 'Edit schedule';

  @override
  String get newSchedule => 'New schedule';

  @override
  String get titleLabel => 'Title';

  @override
  String get typeLabel => 'Type';

  @override
  String get startTimeLabel => 'Start time (YYYY-MM-DDTHH:mm)';

  @override
  String get endTimeLabel => 'End time';

  @override
  String get descriptionPlaceholder =>
      'Description (location, notes, attendees)';

  @override
  String get projectKeyPlaceholder => 'Project (projectKey)';

  @override
  String get createLabel => 'Create';

  @override
  String get projectSkillsTitle => 'Project skills';

  @override
  String get developmentCapabilitiesTooltip => 'Development capabilities';

  @override
  String get allSkillsTooltip => 'All skills';

  @override
  String get noSkillsYet => 'No skills yet';

  @override
  String get addSkillPathInSettings => 'Add skill path in Settings';

  @override
  String get skillsLabel => 'Skills';

  @override
  String get retryLabel => 'Retry';

  @override
  String loadFailedWithColon(Object error) {
    return 'Load failed: $error';
  }

  @override
  String get addFirstProject => 'Add first project';

  @override
  String get editTooltip => 'Edit';

  @override
  String get deleteTooltip => 'Delete';

  @override
  String loadProjectsFailed(Object error) {
    return 'Load projects failed: $error';
  }

  @override
  String get deleteProjectTitleShort => 'Delete project';

  @override
  String deleteProjectConfirmName(Object name) {
    return 'Delete project \"$name\"?';
  }

  @override
  String projectDeletedSnack(Object name) {
    return 'Project deleted: $name';
  }

  @override
  String get useLabel => 'Use';

  @override
  String get notConnectedToProxyShort => 'Not connected to Proxy';

  @override
  String get errorPrefix => 'Error: ';

  @override
  String get manageProjectsTitle => 'Manage Projects';

  @override
  String get noProjectsFound => 'No projects found.';

  @override
  String errorColon(Object error) {
    return 'Error: $error';
  }

  @override
  String deleteProjectConfirmFull(Object name, Object key) {
    return 'Are you sure you want to delete \"$name\" (Key: $key)?';
  }

  @override
  String get cancelLabelCap => 'Cancel';

  @override
  String projectDeletedSnackFull(Object name) {
    return 'Project deleted: $name';
  }

  @override
  String deleteFailedSnackFull(Object error) {
    return 'Failed to delete project: $error';
  }

  @override
  String get deleteLabelCap => 'Delete';

  @override
  String get skillsScreenTitle => 'Skills';

  @override
  String get noSkillsYetShort => 'No skills yet';

  @override
  String get addSkillPathInSettingsShort => 'Add skill path in Settings';

  @override
  String get copiedToClipboardShort => 'Copied to clipboard';

  @override
  String get codeCopiedShort => 'Code copied';

  @override
  String get ipPortHint => '127.0.0.1';

  @override
  String get portHintShort => '8443';

  @override
  String get pinDash => '—';

  @override
  String minutesAgo(Object count) {
    return '$count min ago';
  }

  @override
  String hoursAgo(Object count) {
    return '$count hr ago';
  }

  @override
  String daysAgo(Object count) {
    return '$count days ago';
  }

  @override
  String daysLater(Object count) {
    return 'In $count days';
  }

  @override
  String get taskStatusPending => 'Pending';

  @override
  String get taskStatusConfirmed => 'Confirmed';

  @override
  String get taskStatusInProgress => 'In Progress';

  @override
  String get taskStatusPlanned => 'Planned';

  @override
  String get taskStatusCompleted => 'Completed';

  @override
  String get taskStatusCancelled => 'Cancelled';

  @override
  String get taskStatusFailed => 'Failed';

  @override
  String get taskStatusPlanning => 'Planning';

  @override
  String get taskStatusCoding => 'Coding';

  @override
  String get taskStatusTesting => 'Testing';

  @override
  String get taskStatusSubmitting => 'Submitting';

  @override
  String get taskPriorityP0 => 'P0 Critical';

  @override
  String get taskPriorityP1 => 'P1 High';

  @override
  String get taskPriorityP2 => 'P2 Medium';

  @override
  String get taskPriorityP3 => 'P3 Low';

  @override
  String get feedbackTypeDone => 'Completed';

  @override
  String get feedbackTypeHasIssue => 'Has Issue';

  @override
  String get overdue => 'Overdue';

  @override
  String get untitledConversation => 'Untitled conversation';

  @override
  String get scheduleStatusScheduled => 'Scheduled';

  @override
  String get scheduleStatusInProgress => 'In Progress';

  @override
  String get scheduleStatusCompleted => 'Completed';

  @override
  String get scheduleStatusCancelled => 'Cancelled';

  @override
  String get scheduleStatusLabel => 'Status';

  @override
  String get changeScheduleStatus => 'Change Status';

  @override
  String scheduleStatusChangeSuccess(String status) {
    return 'Status updated to \"$status\"';
  }

  @override
  String get scheduleStatusChangeFailed => 'Failed to update status';

  @override
  String get scheduleDetailTitle => 'Schedule detail';

  @override
  String get linkedTasks => 'Linked tasks';

  @override
  String get noLinkedTasks => 'No linked tasks';
}
