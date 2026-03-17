// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'XAssistant';

  @override
  String get appSubtitle => 'xassistant 的 AI 助手';

  @override
  String get navHome => '首页';

  @override
  String get navTasks => '任务';

  @override
  String get navSchedule => '日程';

  @override
  String get navMessages => '消息';

  @override
  String get navSettings => '设置';

  @override
  String get settings => '设置';

  @override
  String get connection => '连接';

  @override
  String get pairNewDevice => '配对新设备';

  @override
  String get setManualProxy => '设置手动代理';

  @override
  String get bypassPairingHint => '跳过配对直接连接';

  @override
  String get connectedDevice => '已连接设备';

  @override
  String deviceInfo(Object deviceName, Object ip, Object port) {
    return '$deviceName ($ip:$port)';
  }

  @override
  String get disconnect => '断开连接';

  @override
  String get connectionMayHaveIssue => '连接可能有问题';

  @override
  String get diagnose => '诊断';

  @override
  String get connectionDiagnosis => '连接诊断';

  @override
  String get checkingConnection => '检查连接...';

  @override
  String get errorLoadingConnection => '加载连接失败';

  @override
  String get proxyConfig => '代理配置';

  @override
  String get proxyConfigSubtitle => '启动、关闭代理与启动参数管理';

  @override
  String get openclawSkills => 'OpenClaw 技能';

  @override
  String get addSkillPath => '添加技能路径';

  @override
  String get cannotLoadSkillPaths => '无法加载技能路径';

  @override
  String get xAssistantProjects => 'X助手 / 项目管理';

  @override
  String get manageProjects => '管理项目';

  @override
  String get projectsSubtitle => '查看、添加与编辑项目';

  @override
  String projectsCount(Object count) {
    return '共 $count 个项目';
  }

  @override
  String get loading => '加载中...';

  @override
  String get voice => '语音';

  @override
  String get textToSpeech => '文字转语音';

  @override
  String get readAloud => '朗读回复';

  @override
  String get speechRate => '语速';

  @override
  String get normal => '正常';

  @override
  String get notifications => '通知';

  @override
  String get systemNotification => '系统通知';

  @override
  String get systemNotificationSubtitle => '任务完成时推送系统通知';

  @override
  String get viewMessages => '查看消息';

  @override
  String get viewNotificationHistory => '查看应用内通知历史';

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get system => '跟随系统';

  @override
  String get about => '关于';

  @override
  String get version => '版本';

  @override
  String get github => 'GitHub';

  @override
  String get cancel => '取消';

  @override
  String get add => '添加';

  @override
  String get path => '路径';

  @override
  String get pathHint => '/path/to/skills 或 ~/skills';

  @override
  String get disconnectConfirmTitle => '断开连接';

  @override
  String get disconnectConfirmMessage => '确定要断开与此电脑的连接吗？';

  @override
  String get resetPinTitle => '重置 PIN 码';

  @override
  String get resetPinMessage => '确定要重置 PIN 码吗？重置后旧 PIN 将失效，需使用新 PIN 重新配对。';

  @override
  String currentPin(Object pin) {
    return '当前 PIN: $pin';
  }

  @override
  String get confirmReset => '确定重置';

  @override
  String pinResetSuccess(Object pin) {
    return 'PIN 码已重置为：$pin';
  }

  @override
  String resetFailed(Object error) {
    return '重置失败：$error';
  }

  @override
  String get editConnection => '编辑连接';

  @override
  String get ipAddress => 'IP 地址';

  @override
  String get port => '端口';

  @override
  String get pinCode => 'PIN 码';

  @override
  String get pinUseSavedHint => '使用已保存的 PIN (或输入新的)';

  @override
  String get pinEnterHint => '输入 PIN 码';

  @override
  String get leaveEmptyUseSavedPin => '留空则使用已保存的 PIN 码';

  @override
  String get connect => '连接';

  @override
  String pairFailed(Object error) {
    return '配对失败：$error';
  }

  @override
  String get pleaseFillAllFields => '请填写所有字段';

  @override
  String get diagnosisCurrentState => '当前状态';

  @override
  String get diagnosisSavedIp => '保存的IP';

  @override
  String get diagnosisFailCount => '连续失败';

  @override
  String diagnosisFailCountValue(Object count) {
    return '$count 次';
  }

  @override
  String get close => '关闭';

  @override
  String get rePair => '重新配对';

  @override
  String get refresh => '刷新';

  @override
  String get stateUnknown => '未知';

  @override
  String get stateConnected => '已连接';

  @override
  String get stateConnecting => '正在连接...';

  @override
  String get stateNetworkError => '网络错误';

  @override
  String get stateIpChanged => 'IP可能已变化';

  @override
  String get stateAuthError => '认证错误';

  @override
  String pinCodeReusable(Object pin) {
    return 'PIN: $pin (可重复使用)';
  }

  @override
  String get resetPinTooltip => '重置 PIN 码';

  @override
  String get language => '语言';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get taskList => '任务列表';

  @override
  String get taskDetail => '任务详情';

  @override
  String get taskNotFound => '任务不存在';

  @override
  String get addTask => '新建任务';

  @override
  String get editTask => '编辑任务';

  @override
  String get save => '保存';

  @override
  String get filterAll => '全部';

  @override
  String get filterPending => '待确认';

  @override
  String get filterInProgress => '执行中';

  @override
  String get filterCompleted => '已完成';

  @override
  String get emptyTasksAll => '没有待处理的任务';

  @override
  String get emptyTasksPending => '没有待确认的任务';

  @override
  String get emptyTasksInProgress => '没有执行中的任务';

  @override
  String get emptyTasksCompleted => '还没有已完成的任务';

  @override
  String get dashboardInProgress => '执行中';

  @override
  String get dashboardPending => '待确认';

  @override
  String get greetingNight => '夜深了 🌙';

  @override
  String get greetingMorning => '早上好 ☀️';

  @override
  String get greetingNoon => '中午好 🌤';

  @override
  String get greetingAfternoon => '下午好 ⛅';

  @override
  String get greetingEvening => '晚上好 🌙';

  @override
  String get scheduleArrow => '日程 →';

  @override
  String get weekdaySun => '日';

  @override
  String get weekdayMon => '一';

  @override
  String get weekdayTue => '二';

  @override
  String get weekdayWed => '三';

  @override
  String get weekdayThu => '四';

  @override
  String get weekdayFri => '五';

  @override
  String get weekdaySat => '六';

  @override
  String get typeCommand => '输入指令...';

  @override
  String get cancelTooltip => '取消';

  @override
  String get historyTooltip => '历史';

  @override
  String get notConnectedToServer => '未连接到服务器';

  @override
  String get waitForConversation => '请等待当前对话完成后再发送';

  @override
  String get fixErrors => '修复错误';

  @override
  String get runTests => '运行测试';

  @override
  String get explainCode => '解释代码';

  @override
  String get quickResponse => '快捷回复';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get retry => '重试';

  @override
  String get connectionError => '连接错误，请检查网络。';

  @override
  String get disconnectedFromServer => '已与服务器断开连接。';

  @override
  String get reconnect => '重新连接';

  @override
  String agentBackendError(Object error) {
    return 'Agent 后端：$error';
  }

  @override
  String get agentBackendDisconnected => 'Agent 后端未连接，回复可能延迟。';

  @override
  String get fixErrorsCommand => '修复当前文件中的错误';

  @override
  String get runTestsCommand => '运行测试';

  @override
  String get explainCodeCommand => '解释这段代码';

  @override
  String get commandHistory => '指令历史';

  @override
  String get clearHistory => '清空历史';

  @override
  String get clearHistoryConfirm => '确定要清空所有指令历史吗？此操作无法撤销。';

  @override
  String get noCommandHistory => '暂无指令历史';

  @override
  String get messages => '消息';

  @override
  String get noNotifications => '暂无消息';

  @override
  String get notificationsHint => '任务完成后将在这里收到通知';

  @override
  String get markAllRead => '全部已读';

  @override
  String get markAllReadConfirm => '确定要将所有消息标记为已读吗？';

  @override
  String get clearMessages => '清空消息';

  @override
  String get clearMessagesConfirm => '确定要清空所有消息吗？此操作无法撤销。';

  @override
  String get confirm => '确定';

  @override
  String get clear => '清空';

  @override
  String get connectToComputer => '连接电脑';

  @override
  String get startProxyFirst => '启动/配置代理后再连接';

  @override
  String get proxyConfigNav => '代理配置';

  @override
  String get scanQr => '扫码';

  @override
  String get manual => '手动';

  @override
  String get connecting => '连接中...';

  @override
  String get macosProxyHint => 'macOS：若代理未启动，请先前往代理配置页启动代理';

  @override
  String get goToProxyConfig => '去代理配置';

  @override
  String get scanQrHint => '请扫描代理服务显示的二维码';

  @override
  String get runProxyHint => '在代理目录执行 \"go run . -workdir /path/to/project\"';

  @override
  String get proxyNotStartedTitle => '代理未启动？';

  @override
  String get proxyNotStartedSubtitle => '先前往代理配置页启动代理后再填写连接信息';

  @override
  String get enterConnectionDetails => '填写连接信息';

  @override
  String get findOnComputer => '在电脑运行代理服务时可在电脑上查看这些信息';

  @override
  String get computerIp => '电脑 IP 地址';

  @override
  String get ipHint => '192.168.1.100';

  @override
  String get pinHint => '123456';

  @override
  String get directProxyOverride => '直接代理覆盖';

  @override
  String get directProxyOverrideMessage => '跳过配对直接连接。（仅在配对失败时使用）';

  @override
  String get connectDirectly => '直接连接';

  @override
  String get connectionSuccess => '连接成功，已同步技能和项目';

  @override
  String connectionFailed(Object error) {
    return '连接失败：$error';
  }

  @override
  String get manualProxyUrl => '手动代理 URL';

  @override
  String get initializing => '初始化中...';

  @override
  String get checkingConnectionStatus => '正在检查连接...';

  @override
  String connectingTo(Object ip) {
    return '正在连接 $ip...';
  }

  @override
  String get tokenExpiredRepairing => 'Token 已过期，正在重新配对...';

  @override
  String get connectionFailedRepair => '连接失败，正在尝试重新配对...';

  @override
  String get connectionFailedPairAgain => '连接失败，请重新配对';

  @override
  String get proxyConfigTitle => '代理配置';

  @override
  String get proxyConfigMacOnly => '代理配置仅支持 macOS';

  @override
  String get systemSettings => '系统设置';

  @override
  String get proxyConnectionInfo => '代理连接信息（IP / 端口 / PIN）';

  @override
  String get ipLabel => 'IP';

  @override
  String get portLabel => '端口';

  @override
  String get pinOptional => 'PIN（6 位）';

  @override
  String get pinOptionalHint => '填写后启动将自动配对并连接';

  @override
  String get afterStartUseInfo => '启动后将使用上述信息自动连接。';

  @override
  String get pleaseStartProxyFirst => '请先启动代理';

  @override
  String get noSavedConnectionHint =>
      '未保存连接。请先在此页启动代理，代理启动后会显示二维码，再点击「去配对」扫码连接。';

  @override
  String get proxyRunning => '代理已运行';

  @override
  String get proxyChecking => '检测中...';

  @override
  String get proxyNotRunning => '代理未运行';

  @override
  String get detect => '检测';

  @override
  String get proxyPathLabel => '代理程序路径';

  @override
  String get proxyPathHint => '留空则使用 .app 内代理';

  @override
  String get startProxy => '启动代理';

  @override
  String get startingProxy => '正在启动代理...';

  @override
  String get startingProxyConnect => '正在启动代理，稍后自动连接...';

  @override
  String get proxyStartChecking => '代理启动中，正在自动检测...';

  @override
  String startFailed(Object error) {
    return '启动失败：$error';
  }

  @override
  String get proxyStopped => '已关闭代理';

  @override
  String get stopProxy => '关闭代理';

  @override
  String get stopFailed => '关闭请求失败';

  @override
  String get launchCommand => '启动命令（便于排查）';

  @override
  String get copy => '复制';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get goToPair => '去配对（代理启动后扫码）';

  @override
  String get enterApp => '进入应用';

  @override
  String loadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get openInCursor => '已在 Cursor 中打开项目';

  @override
  String get cannotOpenCursor => '无法打开项目，可能缺少相关配置';

  @override
  String get selectDirectory => '选择目录';

  @override
  String get proxyLaunchParams => '代理启动参数';

  @override
  String get enableOpenClaw => '启用 OpenClaw';

  @override
  String get openClawToken => 'OpenClaw Token';

  @override
  String get openClawUrlOptional => 'OpenClaw URL（可选）';

  @override
  String get allowLocalNoAuth => '允许本地无鉴权';

  @override
  String get skillsPath => '技能路径';

  @override
  String get workdirOptional => '工作目录（可选）';

  @override
  String get saveLaunchParams => '保存启动参数';

  @override
  String get launchParamsSaved => '启动参数已保存';

  @override
  String get noLogPath => '未配置日志路径';

  @override
  String get proxyPathNotSet => '未配置代理路径';

  @override
  String logNotGenerated(Object path) {
    return '日志文件尚未生成: $path';
  }

  @override
  String get logOpened => '已用默认应用打开日志';

  @override
  String get viewLog => '查看日志';

  @override
  String get proxyStatusNotDetected => '代理状态未检测';

  @override
  String get proxyStartSuccess => '代理已运行，正在连接...';

  @override
  String get proxyStartWaitCheck => '代理可能仍在启动，请稍后点「检测」';

  @override
  String get pleasePairFirst => '请先配对或配置连接后再检测/启动代理';

  @override
  String get loadingConnection => '加载连接信息...';

  @override
  String get startProxyPleaseWait => '正在启动代理，请稍候...';

  @override
  String get autoPairedConnected => '已自动配对并连接';

  @override
  String get autoConnectFailed => '自动连接失败，请手动去配对';

  @override
  String get logPathLabel => '日志文件路径';

  @override
  String get logPathHint => '留空使用默认 ~/Library/Logs/xassistant-proxy/proxy.log';

  @override
  String get delete => '删除';

  @override
  String get deleteTask => '删除任务';

  @override
  String deleteTaskConfirmMessage(Object title) {
    return '确定要删除「$title」吗？此操作不可撤销。';
  }

  @override
  String get cancelTask => '取消任务';

  @override
  String get submitFeedback => '提交反馈';

  @override
  String get feedbackSubmitted => '反馈已提交';

  @override
  String get deleteMessage => '删除消息';

  @override
  String get deleteMessageConfirm => '确定要删除这条消息吗？';

  @override
  String get selectTaskProject => '选择任务所属项目';

  @override
  String get startingCursorAgent => '正在启动 Cursor Agent...';

  @override
  String get startingCcrAgent => '正在启动 CCR Agent...';

  @override
  String get openInCursorLabel => 'Agent 状态';

  @override
  String get planOnly => '仅生成计划';

  @override
  String get confirmTaskSkipPlan => '确认任务 (跳过Plan)';

  @override
  String get startExecution => '开始执行';

  @override
  String get submitLabel => '提交 (Submit)';

  @override
  String get runTestLabel => '运行测试 (Test)';

  @override
  String get markComplete => '标记完成';

  @override
  String get openingIterm2 => '正在打开 iTerm2...';

  @override
  String get cannotOpenTmux => '无法打开 tmux，确认 Agent 正在运行';

  @override
  String commandCopied(Object command) {
    return '已复制命令: $command';
  }

  @override
  String get generatingPlan => '正在生成计划...';

  @override
  String generateFailed(Object error) {
    return '生成失败: $error';
  }

  @override
  String executingPhase(Object phase) {
    return '正在执行 $phase 阶段...';
  }

  @override
  String phaseExecutionFailed(Object error) {
    return '阶段执行失败: $error';
  }

  @override
  String get phaseSwitchFailed => '阶段切换失败';

  @override
  String phaseUpdated(Object phase) {
    return '阶段已更新为: $phase';
  }

  @override
  String statusUpdated(Object status) {
    return '状态已更新为: $status';
  }

  @override
  String startingAgent(Object backend) {
    return '正在启动 $backend Agent...';
  }

  @override
  String get codeCopied => '代码已复制';

  @override
  String get developmentCapabilities => '开发能力';

  @override
  String get noProjects => '暂无项目';

  @override
  String get addProjectToUse => '添加项目以使用开发能力';

  @override
  String get requiredInfo => '必填信息';

  @override
  String get optionalInfo => '选填信息';

  @override
  String saveFailed(Object error) {
    return '保存失败：$error';
  }

  @override
  String get notConnectedPleaseConnect => '未连接到服务端，请先在设置中完成连接';

  @override
  String get taskCompletedTitle => '任务已完成';

  @override
  String get taskFailedTitle => '任务执行失败';

  @override
  String get taskProgressTitle => '任务进度更新';

  @override
  String get taskTitle => '任务标题';

  @override
  String get taskTitleHint => '输入任务名称...';

  @override
  String get taskTitleRequired => '请输入任务标题';

  @override
  String get descriptionOptional => '描述（可选）';

  @override
  String get descriptionHint => '添加任务描述...';

  @override
  String get project => '项目';

  @override
  String get priority => '优先级';

  @override
  String get source => '来源';

  @override
  String get sourceManual => '手动';

  @override
  String get sourceOpenClaw => 'OpenClaw';

  @override
  String get sourceCursor => 'Cursor';

  @override
  String get sourceSkill => '技能';

  @override
  String get agentOptional => '执行 Agent (可选)';

  @override
  String get agentCursor => 'Cursor';

  @override
  String get agentCcr => 'CCR';

  @override
  String get agentClaude => 'Claude';

  @override
  String get deadlineOptional => '截止时间（可选）';

  @override
  String get selectDate => '选择日期';

  @override
  String get selectTime => '选择时间';

  @override
  String get projectKeyManualHint => '项目 Key（无注册项目时手动填写）';

  @override
  String get projectKeyExample => '例如 xassistant';

  @override
  String get noProjectSelected => '— 不选择 —';

  @override
  String get projectKeyFallbackHint => '项目 Key（加载失败时手动填写）';

  @override
  String get cursorAgentStartedInTmux => 'Cursor Agent 已在 tmux 中启动';

  @override
  String get ccrAgentStartedInTmux => 'CCR Agent 已在 tmux 中启动';

  @override
  String get startFailedShort => '启动失败';

  @override
  String get runWithCursor => '用 Cursor 执行';

  @override
  String get runWithCcr => '用 CCR 执行';

  @override
  String get viewAgent => '查看 Agent';

  @override
  String get preferredAgent => '首选 Agent';

  @override
  String get projectKey => '项目 Key';

  @override
  String get createdAt => '创建时间';

  @override
  String get deadline => '截止时间';

  @override
  String get completedAt => '完成时间';

  @override
  String get executionPlan => '执行计划';

  @override
  String get planLoadFailed =>
      '无法加载计划详情（请确认 proxy 的 --workdir 与任务 plan 文件路径一致）';

  @override
  String get description => '描述';

  @override
  String get feedback => '反馈';

  @override
  String get completed => '已完成';

  @override
  String get hasIssue => '有问题';

  @override
  String get describeIssue => '请描述遇到的问题...';

  @override
  String get addNoteOptional => '添加备注（可选）...';

  @override
  String get phasePlan => '计划';

  @override
  String get phaseCode => '开发';

  @override
  String get phaseTest => '测试';

  @override
  String get phaseDone => '完成';

  @override
  String statusPhaseFormat(Object status, Object phase) {
    return '状态: $status$phase';
  }

  @override
  String get statusLabel => '状态';

  @override
  String get phaseLabel => '阶段';

  @override
  String get changePhase => '修改阶段';

  @override
  String get changeStatus => '修改状态';

  @override
  String get executionUses => '本次执行使用:';

  @override
  String get ccrExecute => 'CCR执行';

  @override
  String get cursorExecute => 'Cursor执行';

  @override
  String get retryCcr => '重试 CCR';

  @override
  String get retryCursor => '重试 Cursor';

  @override
  String messageCount(Object count) {
    return '$count 条消息';
  }

  @override
  String get justNow => '刚刚';

  @override
  String todayAt(Object time) {
    return '今天 $time';
  }

  @override
  String get tomorrow => '明天';

  @override
  String get yesterday => '昨天';

  @override
  String get unknownError => '未知错误';

  @override
  String get proxySection => '代理';

  @override
  String get proxyStartSuccessSnack => '代理已运行，正在连接...';

  @override
  String get proxyStartWaitSnack => '代理可能仍在启动，请稍后点「检测」';

  @override
  String get pleasePairOrConfigThenDetect => '请先配对或配置连接后再检测/启动代理';

  @override
  String get proxyStatusNotDetectedShort => '代理状态未检测';

  @override
  String get proxyCheckingShort => '检测中...';

  @override
  String get proxyRunningShort => '代理已运行';

  @override
  String get proxyNotRunningShort => '代理未运行';

  @override
  String get detectFailed => '检测失败';

  @override
  String get detectLabel => '检测';

  @override
  String get launchParamsSavedSnack => '启动参数已保存';

  @override
  String get proxyPathLabelShort => '代理程序路径';

  @override
  String get proxyPathHintLong => '/path/to/xassistant-proxy 或 proxy 可执行文件路径';

  @override
  String get startProxyPleaseWaitSnack => '正在启动代理，请稍候...';

  @override
  String get startProxyLabel => '启动代理';

  @override
  String get loadingConnectionTitle => '加载连接信息...';

  @override
  String loadFailedWithError(Object error) {
    return '加载失败: $error';
  }

  @override
  String get proxyLaunchParamsTitle => '代理启动参数';

  @override
  String get enableOpenClawTitle => '启用 OpenClaw';

  @override
  String get enableOpenClawSubtitle => '--openclaw';

  @override
  String get openClawTokenLabel => 'OpenClaw Token';

  @override
  String get openClawTokenHint => '--openclaw-token';

  @override
  String get openClawUrlLabel => 'OpenClaw URL（可选）';

  @override
  String get openClawUrlHint => '--openclaw-url';

  @override
  String get allowLocalNoAuthTitle => '允许本地无鉴权';

  @override
  String get allowLocalNoAuthSubtitle =>
      '--allow-local-no-auth（skill 脚本调用 /api/tasks）';

  @override
  String get skillsPathLabel => '技能路径';

  @override
  String get skillsPathHint => '--skills-path，如 ../skills';

  @override
  String get selectDirectoryLabel => '选择目录';

  @override
  String get workdirLabel => '工作目录（可选）';

  @override
  String get workdirHint => '--workdir';

  @override
  String get saveLaunchParamsLabel => '保存启动参数';

  @override
  String get versionPlaceholder => '1.0.0';

  @override
  String get projectCreated => '项目已创建';

  @override
  String get projectUpdated => '项目已更新';

  @override
  String saveFailedWithError(Object error) {
    return '保存失败：$error';
  }

  @override
  String get editProject => '编辑项目';

  @override
  String get addProject => '添加项目';

  @override
  String get requiredInfoTitle => '必填信息';

  @override
  String get requiredInfoSubtitle => '项目标识、名称与本地路径为必填项';

  @override
  String get projectKeyLabel => '项目标识';

  @override
  String get projectKeyHint => '例如：my_app';

  @override
  String get projectKeyHelper => '创建后不可修改，用于唯一识别项目';

  @override
  String get projectNameLabel => '项目名称';

  @override
  String get projectNameHint => '例如：我的应用';

  @override
  String get enterProjectKey => '请输入项目标识';

  @override
  String get enterProjectName => '请输入项目名称';

  @override
  String get projectPathLabel => '项目路径';

  @override
  String get projectPathHint => '例如：/Users/xxx/workspace/my_app';

  @override
  String get projectPathHelper => '本地绝对路径，指向项目根目录';

  @override
  String get enterProjectPath => '请输入项目路径';

  @override
  String get optionalInfoTitle => '选填信息';

  @override
  String get optionalInfoSubtitle => '类型、技术栈、负责人等可按需填写';

  @override
  String get typeOptionalLabel => '类型（选填）';

  @override
  String get typeOptionalHint => '例如：backend-service、tool';

  @override
  String get techStackLabel => '技术栈（选填）';

  @override
  String get techStackHint => '例如：Flutter, Dart, Go（逗号分隔）';

  @override
  String get ownerLabel => '负责人（选填）';

  @override
  String get ownerHint => '例如：张三';

  @override
  String get statusOptionalLabel => '状态（选填）';

  @override
  String get statusOptionalHint => '例如：active、archived';

  @override
  String get descriptionOptionalLabel => '描述（选填）';

  @override
  String get descriptionOptionalHint => '简要描述项目用途';

  @override
  String get saving => '保存中…';

  @override
  String get saveChanges => '保存修改';

  @override
  String get createProject => '创建项目';

  @override
  String get selectCapabilityToRun => '选择能力执行开发任务';

  @override
  String get registeredProjects => '已注册项目';

  @override
  String get addLabel => '添加';

  @override
  String get selectExecutor => '选择执行器';

  @override
  String get projectLabel => '项目';

  @override
  String get taskTitleLabel => '任务标题';

  @override
  String get taskTitleExample => '例如: 优化库存同步API';

  @override
  String get requirementLabel => '需求描述';

  @override
  String get requirementHint => '详细说明需要实现的功能';

  @override
  String get cancelLabel => '取消';

  @override
  String get executeLabel => '执行';

  @override
  String get pleaseEnterTaskTitle => '请输入任务标题';

  @override
  String get notConnectedToProxy => '未连接到代理服务器';

  @override
  String get executing => '正在执行...';

  @override
  String taskCreatedSnack(Object taskId) {
    return '任务已创建: $taskId';
  }

  @override
  String sentToAgentSnack(Object id) {
    return '已发送到 Agent: $id';
  }

  @override
  String executeFailedSnack(Object error) {
    return '执行失败: $error';
  }

  @override
  String get addProjectTitle => '添加项目';

  @override
  String get projectKeyKeyLabel => '项目键 (Key)';

  @override
  String get projectKeyKeyHint => '例如: my_project';

  @override
  String get projectNameKeyLabel => '项目名称';

  @override
  String get projectNameKeyHint => '例如: 库存系统';

  @override
  String get projectPathKeyLabel => '项目路径';

  @override
  String get projectPathKeyHint => '/path/to/project';

  @override
  String get descriptionKeyLabel => '描述（可选）';

  @override
  String get pleaseFillKeyNamePath => '请填写项目键、名称和路径';

  @override
  String addFailedSnack(Object error) {
    return '添加失败: $error';
  }

  @override
  String get deleteProjectTitle => '删除项目?';

  @override
  String deleteProjectConfirm(Object key) {
    return '确定要删除项目 \"$key\" 吗？';
  }

  @override
  String get deleteLabel => '删除';

  @override
  String deleteFailedSnack(Object error) {
    return '删除失败: $error';
  }

  @override
  String get pleaseAddProjectFirst => '请先添加项目';

  @override
  String get scheduleTitle => '日程';

  @override
  String get byDay => '按日';

  @override
  String get weekView => '一周';

  @override
  String get noScheduleToday => '当天无日程';

  @override
  String get deleteScheduleTitle => '删除日程';

  @override
  String deleteScheduleConfirm(Object title) {
    return '确定删除「$title」？';
  }

  @override
  String get deleteLabelRed => '删除';

  @override
  String get weekdayShort => '日,一,二,三,四,五,六';

  @override
  String dateFormatFull(Object weekday, Object month, Object day) {
    return '$month月$day日 $weekday';
  }

  @override
  String get eventTypeMeeting => '会议';

  @override
  String get eventTypeDeadline => '截止';

  @override
  String get eventTypeSocial => '社交';

  @override
  String get eventTypeReview => '评审';

  @override
  String get eventTypeOther => '其他';

  @override
  String get noItems => '无事项';

  @override
  String get editSchedule => '编辑日程';

  @override
  String get newSchedule => '新建日程';

  @override
  String get titleLabel => '标题';

  @override
  String get typeLabel => '类型';

  @override
  String get startTimeLabel => '开始时间 (YYYY-MM-DDTHH:mm)';

  @override
  String get endTimeLabel => '结束时间';

  @override
  String get descriptionPlaceholder => '描述（可填写地点、备注、参与人等）';

  @override
  String get projectKeyPlaceholder => '项目 (projectKey)';

  @override
  String get createLabel => '创建';

  @override
  String get projectSkillsTitle => '项目技能';

  @override
  String get developmentCapabilitiesTooltip => '开发能力';

  @override
  String get allSkillsTooltip => '全部技能';

  @override
  String get noSkillsYet => '暂无技能';

  @override
  String get addSkillPathInSettings => '请在设置中添加技能路径';

  @override
  String get skillsLabel => '技能';

  @override
  String get retryLabel => '重试';

  @override
  String loadFailedWithColon(Object error) {
    return '加载失败: $error';
  }

  @override
  String get addFirstProject => '添加第一个项目';

  @override
  String get editTooltip => '编辑';

  @override
  String get deleteTooltip => '删除';

  @override
  String loadProjectsFailed(Object error) {
    return '加载项目失败: $error';
  }

  @override
  String get deleteProjectTitleShort => '删除项目';

  @override
  String deleteProjectConfirmName(Object name) {
    return '确定要删除项目 \"$name\" 吗？';
  }

  @override
  String projectDeletedSnack(Object name) {
    return '已删除项目: $name';
  }

  @override
  String get useLabel => '使用';

  @override
  String get notConnectedToProxyShort => '未连接到 Proxy';

  @override
  String get errorPrefix => '错误: ';

  @override
  String get manageProjectsTitle => 'Manage Projects';

  @override
  String get noProjectsFound => 'No projects found.';

  @override
  String errorColon(Object error) {
    return '错误: $error';
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
  String get skillsScreenTitle => '技能';

  @override
  String get noSkillsYetShort => '暂无技能';

  @override
  String get addSkillPathInSettingsShort => '请在设置中添加技能路径';

  @override
  String get copiedToClipboardShort => 'Copied to clipboard';

  @override
  String get codeCopiedShort => '代码已复制';

  @override
  String get ipPortHint => '127.0.0.1';

  @override
  String get portHintShort => '8443';

  @override
  String get pinDash => '—';

  @override
  String minutesAgo(Object count) {
    return '$count 分钟前';
  }

  @override
  String hoursAgo(Object count) {
    return '$count 小时前';
  }

  @override
  String daysAgo(Object count) {
    return '$count 天前';
  }

  @override
  String daysLater(Object count) {
    return '$count 天后';
  }

  @override
  String get taskStatusPending => '待确认';

  @override
  String get taskStatusConfirmed => '已确认';

  @override
  String get taskStatusInProgress => '执行中';

  @override
  String get taskStatusPlanned => '已计划';

  @override
  String get taskStatusCompleted => '已完成';

  @override
  String get taskStatusCancelled => '已取消';

  @override
  String get taskStatusFailed => '执行失败';

  @override
  String get taskStatusPlanning => '计划中';

  @override
  String get taskStatusCoding => '执行中';

  @override
  String get taskStatusTesting => '测试中';

  @override
  String get taskStatusSubmitting => '提交中';

  @override
  String get taskPriorityP0 => 'P0 紧急';

  @override
  String get taskPriorityP1 => 'P1 高';

  @override
  String get taskPriorityP2 => 'P2 中';

  @override
  String get taskPriorityP3 => 'P3 低';

  @override
  String get feedbackTypeDone => '已完成';

  @override
  String get feedbackTypeHasIssue => '有问题';

  @override
  String get overdue => '已逾期';

  @override
  String get untitledConversation => '无标题对话';

  @override
  String get scheduleStatusScheduled => '待开始';

  @override
  String get scheduleStatusInProgress => '进行中';

  @override
  String get scheduleStatusCompleted => '已完成';

  @override
  String get scheduleStatusCancelled => '已取消';

  @override
  String get scheduleStatusLabel => '状态';

  @override
  String get changeScheduleStatus => '切换状态';

  @override
  String scheduleStatusChangeSuccess(String status) {
    return '状态已更新为「$status」';
  }

  @override
  String get scheduleStatusChangeFailed => '状态更新失败';

  @override
  String get scheduleDetailTitle => '日程详情';

  @override
  String get linkedTasks => '关联任务';

  @override
  String get noLinkedTasks => '暂无关联任务';
}
