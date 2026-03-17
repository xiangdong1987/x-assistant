// Parses voice commands and Claude responses to enable voice control

class VoiceCommand {
  final VoiceCommandType type;
  final String? value;
  final String originalText;

  VoiceCommand({
    required this.type,
    this.value,
    required this.originalText,
  });
}

enum VoiceCommandType {
  confirm,      // 确认、是、好的、同意
  cancel,       // 取消、否、不要、算了
  selectOption, // 选择第X个、X
  goBack,       // 返回、上一步
  stop,         // 停止、中断
  retry,        // 重试、再来一次
  normal,       // 普通命令
}

class CommandParser {
  // 确认相关的关键词
  static const _confirmKeywords = [
    '确认', '确定', '是', '是的', '好', '好的', '同意', '可以', '行', 'OK', 'ok', 'yes',
    '对', '没问题', '执行', '继续', '通过', '批准',
  ];

  // 取消相关的关键词
  static const _cancelKeywords = [
    '取消', '否', '不', '不要', '算了', '不行', '拒绝', 'no', '停', '别',
    '不用', '不需要', '放弃',
  ];

  // 停止相关的关键词
  static const _stopKeywords = [
    '停止', '中断', '中止', '打断', 'stop', '暂停',
  ];

  // 重试相关的关键词
  static const _retryKeywords = [
    '重试', '再试', '再来', '重新', 'retry', '再试一次',
  ];

  // 返回相关的关键词
  static const _backKeywords = [
    '返回', '上一步', '回去', 'back',
  ];

  /// 解析语音命令
  static VoiceCommand parseVoiceCommand(String text) {
    final normalized = text.trim().toLowerCase();

    // 检查选择选项 - "选择第X个" 或纯数字
    final selectMatch = _parseSelectOption(normalized);
    if (selectMatch != null) {
      return VoiceCommand(
        type: VoiceCommandType.selectOption,
        value: selectMatch,
        originalText: text,
      );
    }

    // 检查确认命令
    if (_matchesAny(normalized, _confirmKeywords)) {
      return VoiceCommand(
        type: VoiceCommandType.confirm,
        originalText: text,
      );
    }

    // 检查取消命令
    if (_matchesAny(normalized, _cancelKeywords)) {
      return VoiceCommand(
        type: VoiceCommandType.cancel,
        originalText: text,
      );
    }

    // 检查停止命令
    if (_matchesAny(normalized, _stopKeywords)) {
      return VoiceCommand(
        type: VoiceCommandType.stop,
        originalText: text,
      );
    }

    // 检查重试命令
    if (_matchesAny(normalized, _retryKeywords)) {
      return VoiceCommand(
        type: VoiceCommandType.retry,
        originalText: text,
      );
    }

    // 检查返回命令
    if (_matchesAny(normalized, _backKeywords)) {
      return VoiceCommand(
        type: VoiceCommandType.goBack,
        originalText: text,
      );
    }

    // 普通命令
    return VoiceCommand(
      type: VoiceCommandType.normal,
      originalText: text,
    );
  }

  /// 解析选择选项命令
  static String? _parseSelectOption(String text) {
    // 匹配 "选择第X个"、"第X个"、"选X"
    final patterns = [
      RegExp(r'选择?第?([一二三四五六七八九十\d]+)[个项]?'),
      RegExp(r'^([一二三四五六七八九十\d]+)$'),
      RegExp(r'选?([一二三四五六七八九十\d]+)号?'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return _chineseToNumber(match.group(1)!);
      }
    }

    return null;
  }

  /// 中文数字转阿拉伯数字
  static String _chineseToNumber(String chinese) {
    const map = {
      '一': '1', '二': '2', '三': '3', '四': '4', '五': '5',
      '六': '6', '七': '7', '八': '8', '九': '9', '十': '10',
      '1': '1', '2': '2', '3': '3', '4': '4', '5': '5',
      '6': '6', '7': '7', '8': '8', '9': '9', '10': '10',
    };
    return map[chinese] ?? chinese;
  }

  static bool _matchesAny(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}

/// 响应类型检测
enum ResponseType {
  question,     // 是/否问题
  options,      // 多选项
  confirmation, // 确认提示
  error,        // 错误信息
  progress,     // 进行中
  complete,     // 完成
  normal,       // 普通输出
}

class ResponseAnalysis {
  final ResponseType type;
  final List<String> options;
  final String? question;

  ResponseAnalysis({
    required this.type,
    this.options = const [],
    this.question,
  });
}

class ResponseParser {
  /// 分析 Claude 的响应内容
  static ResponseAnalysis analyzeResponse(String content) {
    final lines = content.split('\n');
    final options = <String>[];

    // 检测是否有选项列表
    final optionPatterns = [
      RegExp(r'^\s*[\d]+[.、)]\s*(.+)$'),      // 1. xxx 或 1、xxx
      RegExp(r'^\s*[-•]\s*(.+)$'),             // - xxx 或 • xxx
      RegExp(r'^\s*\[[\d]+\]\s*(.+)$'),        // [1] xxx
    ];

    for (final line in lines) {
      for (final pattern in optionPatterns) {
        final match = pattern.firstMatch(line.trim());
        if (match != null) {
          options.add(match.group(1)!.trim());
        }
      }
    }

    // 检测是/否问题
    final yesNoPatterns = [
      RegExp(r'[是否要|是否|要不要|确认|同意].+[?？]'),
      RegExp(r'\(y/n\)', caseSensitive: false),
      RegExp(r'\[y/n\]', caseSensitive: false),
      RegExp(r'yes/no', caseSensitive: false),
    ];

    for (final pattern in yesNoPatterns) {
      if (pattern.hasMatch(content)) {
        // 找到问题文本
        final questionMatch = RegExp(r'[^。\n]+[?？]').firstMatch(content);
        return ResponseAnalysis(
          type: ResponseType.question,
          question: questionMatch?.group(0),
        );
      }
    }

    // 检测确认提示
    final confirmPatterns = [
      RegExp(r'确认|确定|继续|proceed', caseSensitive: false),
    ];

    for (final pattern in confirmPatterns) {
      if (pattern.hasMatch(content) && content.contains('?') || content.contains('？')) {
        return ResponseAnalysis(
          type: ResponseType.confirmation,
          question: content,
        );
      }
    }

    // 如果有选项
    if (options.isNotEmpty) {
      return ResponseAnalysis(
        type: ResponseType.options,
        options: options,
      );
    }

    // 检测错误
    if (content.toLowerCase().contains('error') || content.contains('错误') || content.contains('失败')) {
      return ResponseAnalysis(type: ResponseType.error);
    }

    // 检测完成
    if (content.contains('完成') || content.contains('成功') || content.toLowerCase().contains('done')) {
      return ResponseAnalysis(type: ResponseType.complete);
    }

    return ResponseAnalysis(type: ResponseType.normal);
  }
}
