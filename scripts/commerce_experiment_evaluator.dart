/// PROD-07 匿名聚合商业实验的纯 Dart 计算逻辑。
///
/// 本文件只处理计数、口径和决策线，不创建订单、不读取用户数据，也不代表真实
/// 支付已经启动。
library;

/// 商业指标或总体实验的决策状态。
enum CommerceDecisionStatus {
  /// 达到对应继续线。
  continueLine,

  /// 落入调整线。
  adjustLine,

  /// 落入单项或总停止线。
  stopLine,

  /// 输入不足以得出结论。
  insufficientEvidence,

  /// 支付实验前置条件未满足。
  notStarted,
}

/// 商业实验的固定阈值，来源于详设第 21.2 节。
abstract final class CommerceExperimentThresholds {
  static const double localProDepositContinueRate = 0.03;
  static const double localProDepositAdjustRate = 0.01;
  static const double localProFullContinueRate = 0.15;
  static const double localProFullAdjustRate = 0.075;
  static const int localProFullContinueCount = 6;
  static const int localProHighPriceContinueCount = 3;
  static const int localProFullAdjustMinimumCount = 3;
  static const double d7ReturnContinueRate = 0.35;
  static const double d7ReturnAdjustRate = 0.25;
  static const double realmPurchaseContinueRate = 0.15;
  static const double realmPurchaseAdjustRate = 0.08;
  static const double xiaoyoReasonContinueRate = 0.40;
  static const double xiaoyoReasonAdjustRate = 0.20;
  static const int xiaoyoReasonContinueCount = 3;
  static const double authorPurchaseContinueRate = 0.10;
  static const double authorPurchaseAdjustRate = 0.05;
  static const int authorPurchaseContinueCount = 2;
  static const double cloudTtsGrossMarginContinueRate = 0.60;
}

/// 云音色合规与单位经济证据。
final class CloudTtsEvidence {
  /// 创建云音色证据。
  const CloudTtsEvidence({
    required this.licensed,
    required this.privacyApproved,
    required this.grossMarginPercent,
    required this.unitEconomicsFailed,
  });

  /// 是否具备持牌或合法供应商凭证。
  final bool? licensed;

  /// 隐私评审是否通过。
  final bool? privacyApproved;

  /// 目标毛利率，使用百分数表达，例如 60.0 表示 60%。
  final double? grossMarginPercent;

  /// 是否已确认单位经济失败；成本偏高但尚未确认失败时仍可进入调整线。
  final bool? unitEconomicsFailed;

  /// 从匿名聚合 JSON 读取云音色证据。
  factory CloudTtsEvidence.fromJson(Map<String, dynamic> json) {
    return CloudTtsEvidence(
      licensed: _optionalBool(json, 'licensed'),
      privacyApproved: _optionalBool(json, 'privacyApproved'),
      grossMarginPercent: _optionalDouble(json, 'grossMarginPercent'),
      unitEconomicsFailed: _optionalBool(json, 'unitEconomicsFailed'),
    );
  }
}

/// 商业实验只保存匿名聚合计数，不保存用户级记录。
final class CommerceExperimentAggregate {
  /// 创建匿名聚合实验数据。
  const CommerceExperimentAggregate({
    required this.paymentChannelVerified,
    required this.refundDrillVerified,
    required this.ownerApproved,
    required this.qualifiedVisitors,
    required this.localProDeposits,
    required this.validExperienceUsers,
    required this.localProFullPayments,
    required this.localProPaymentsAtOrAbove79,
    required this.d7ReturningUsers,
    required this.completeRealmPreviews,
    required this.realmFullPayments,
    required this.paidInterviewUsers,
    required this.xiaoyoTop3ReasonUsers,
    required this.qualifiedAuthorExperiencers,
    required this.authorFullPayments,
    required this.grossPaidFen,
    required this.refundedFen,
    required this.cloudTts,
  });

  final bool? paymentChannelVerified;
  final bool? refundDrillVerified;
  final bool? ownerApproved;
  final int? qualifiedVisitors;
  final int? localProDeposits;
  final int? validExperienceUsers;
  final int? localProFullPayments;
  final int? localProPaymentsAtOrAbove79;
  final int? d7ReturningUsers;
  final int? completeRealmPreviews;
  final int? realmFullPayments;
  final int? paidInterviewUsers;
  final int? xiaoyoTop3ReasonUsers;
  final int? qualifiedAuthorExperiencers;
  final int? authorFullPayments;
  final int? grossPaidFen;
  final int? refundedFen;
  final CloudTtsEvidence? cloudTts;

  /// 从 JSON 读取数据，并拒绝明显违反隐私边界或计数关系的数据。
  factory CommerceExperimentAggregate.fromJson(Map<String, dynamic> json) {
    _rejectPrivateFields(json);
    final cloudTtsJson = json['cloudTts'];
    if (cloudTtsJson != null && cloudTtsJson is! Map<String, dynamic>) {
      throw const FormatException('cloudTts 必须是对象或 null');
    }
    final aggregate = CommerceExperimentAggregate(
      paymentChannelVerified: _optionalBool(json, 'paymentChannelVerified'),
      refundDrillVerified: _optionalBool(json, 'refundDrillVerified'),
      ownerApproved: _optionalBool(json, 'ownerApproved'),
      qualifiedVisitors: _optionalNonNegativeInt(json, 'qualifiedVisitors'),
      localProDeposits: _optionalNonNegativeInt(json, 'localProDeposits'),
      validExperienceUsers:
          _optionalNonNegativeInt(json, 'validExperienceUsers'),
      localProFullPayments:
          _optionalNonNegativeInt(json, 'localProFullPayments'),
      localProPaymentsAtOrAbove79:
          _optionalNonNegativeInt(json, 'localProPaymentsAtOrAbove79'),
      d7ReturningUsers: _optionalNonNegativeInt(json, 'd7ReturningUsers'),
      completeRealmPreviews:
          _optionalNonNegativeInt(json, 'completeRealmPreviews'),
      realmFullPayments: _optionalNonNegativeInt(json, 'realmFullPayments'),
      paidInterviewUsers: _optionalNonNegativeInt(json, 'paidInterviewUsers'),
      xiaoyoTop3ReasonUsers:
          _optionalNonNegativeInt(json, 'xiaoyoTop3ReasonUsers'),
      qualifiedAuthorExperiencers:
          _optionalNonNegativeInt(json, 'qualifiedAuthorExperiencers'),
      authorFullPayments: _optionalNonNegativeInt(json, 'authorFullPayments'),
      grossPaidFen: _optionalNonNegativeInt(json, 'grossPaidFen'),
      refundedFen: _optionalNonNegativeInt(json, 'refundedFen'),
      cloudTts: cloudTtsJson is Map<String, dynamic>
          ? CloudTtsEvidence.fromJson(cloudTtsJson)
          : null,
    );
    aggregate._validateCountRelationships();
    return aggregate;
  }

  void _validateCountRelationships() {
    _validateAtMost(localProDeposits, qualifiedVisitors, 'localProDeposits');
    _validateAtMost(
      localProFullPayments,
      validExperienceUsers,
      'localProFullPayments',
    );
    _validateAtMost(
      localProPaymentsAtOrAbove79,
      localProFullPayments,
      'localProPaymentsAtOrAbove79',
    );
    _validateAtMost(d7ReturningUsers, validExperienceUsers, 'd7ReturningUsers');
    _validateAtMost(
      realmFullPayments,
      completeRealmPreviews,
      'realmFullPayments',
    );
    _validateAtMost(
      xiaoyoTop3ReasonUsers,
      paidInterviewUsers,
      'xiaoyoTop3ReasonUsers',
    );
    _validateAtMost(
      authorFullPayments,
      qualifiedAuthorExperiencers,
      'authorFullPayments',
    );
    _validateAtMost(refundedFen, grossPaidFen, 'refundedFen');
  }
}

/// 单项商业指标的可追溯结论。
final class CommerceMetricDecision {
  /// 创建一个指标结论。
  const CommerceMetricDecision({
    required this.key,
    required this.status,
    required this.numerator,
    required this.denominator,
    required this.rate,
    required this.reason,
  });

  final String key;
  final CommerceDecisionStatus status;
  final int? numerator;
  final int? denominator;
  final double? rate;
  final String reason;

  /// 转换为机器可读的审计结果。
  Map<String, dynamic> toJson() => {
        'key': key,
        'status': status.name,
        'numerator': numerator,
        'denominator': denominator,
        'rate': rate,
        'reason': reason,
      };
}

/// 商业实验的总体报告。
final class CommerceExperimentReport {
  /// 创建总体报告。
  const CommerceExperimentReport({
    required this.status,
    required this.reason,
    required this.decisions,
    required this.grossPaidFen,
    required this.refundedFen,
    required this.netPaidFen,
  });

  final CommerceDecisionStatus status;
  final String reason;
  final List<CommerceMetricDecision> decisions;
  final int? grossPaidFen;
  final int? refundedFen;
  final int? netPaidFen;

  /// 转换为机器可读的审计结果。
  Map<String, dynamic> toJson() => {
        'status': status.name,
        'reason': reason,
        'grossPaidFen': grossPaidFen,
        'refundedFen': refundedFen,
        'netPaidFen': netPaidFen,
        'decisions': decisions.map((decision) => decision.toJson()).toList(),
      };
}

/// 按详设的前置条件、指标线和总停止线计算报告。
CommerceExperimentReport evaluateCommerceExperiment(
  CommerceExperimentAggregate aggregate,
) {
  final decisions = <CommerceMetricDecision>[
    _localProDepositDecision(aggregate),
    _localProFullDecision(aggregate),
    _d7Decision(aggregate),
    _realmDecision(aggregate),
    _xiaoyoReasonDecision(aggregate),
    _authorDecision(aggregate),
    _cloudTtsDecision(aggregate),
  ];
  final netPaidFen =
      aggregate.grossPaidFen == null || aggregate.refundedFen == null
          ? null
          : aggregate.grossPaidFen! - aggregate.refundedFen!;
  final preconditions = <bool?>[
    aggregate.paymentChannelVerified,
    aggregate.refundDrillVerified,
    aggregate.ownerApproved,
  ];
  if (preconditions.any((value) => value == false)) {
    return CommerceExperimentReport(
      status: CommerceDecisionStatus.notStarted,
      reason: '支付渠道、退款演练或负责人批准未全部通过，实验不得视为已启动',
      decisions: decisions,
      grossPaidFen: aggregate.grossPaidFen,
      refundedFen: aggregate.refundedFen,
      netPaidFen: netPaidFen,
    );
  }
  if (preconditions.any((value) => value == null) ||
      decisions.any(
        (decision) =>
            decision.status == CommerceDecisionStatus.insufficientEvidence,
      )) {
    return CommerceExperimentReport(
      status: CommerceDecisionStatus.insufficientEvidence,
      reason: '实验前置条件或指标证据不完整，不能输出继续/调整/停止结论',
      decisions: decisions,
      grossPaidFen: aggregate.grossPaidFen,
      refundedFen: aggregate.refundedFen,
      netPaidFen: netPaidFen,
    );
  }

  final localProStopped = decisions
      .where(
        (decision) =>
            decision.key == 'localProDepositRate' ||
            decision.key == 'localProFullPaymentRate',
      )
      .any((decision) => decision.status == CommerceDecisionStatus.stopLine);
  final realmStopped = decisions
          .firstWhere((decision) => decision.key == 'realmFullPaymentRate')
          .status ==
      CommerceDecisionStatus.stopLine;
  final status = localProStopped && realmStopped
      ? CommerceDecisionStatus.stopLine
      : decisions.every(
          (decision) => decision.status == CommerceDecisionStatus.continueLine,
        )
          ? CommerceDecisionStatus.continueLine
          : CommerceDecisionStatus.adjustLine;
  final reason = status == CommerceDecisionStatus.stopLine
      ? 'Local Pro 与书境包同时触发停止线，停止普通用户商业系统建设'
      : status == CommerceDecisionStatus.continueLine
          ? '全部指标达到继续线，仍需保留退款、净支付和负责人复核记录'
          : '存在调整项或单项停止项，但未同时触发普通用户总停止线';
  return CommerceExperimentReport(
    status: status,
    reason: reason,
    decisions: decisions,
    grossPaidFen: aggregate.grossPaidFen,
    refundedFen: aggregate.refundedFen,
    netPaidFen: netPaidFen,
  );
}

CommerceMetricDecision _localProDepositDecision(
  CommerceExperimentAggregate aggregate,
) =>
    _ratioDecision(
      key: 'localProDepositRate',
      numerator: aggregate.localProDeposits,
      denominator: aggregate.qualifiedVisitors,
      continueRate: CommerceExperimentThresholds.localProDepositContinueRate,
      adjustRate: CommerceExperimentThresholds.localProDepositAdjustRate,
      label: 'Local Pro 订金率',
    );

CommerceMetricDecision _localProFullDecision(
  CommerceExperimentAggregate aggregate,
) {
  final numerator = aggregate.localProFullPayments;
  final denominator = aggregate.validExperienceUsers;
  if (numerator == null || denominator == null || denominator <= 0) {
    return _insufficient('localProFullPaymentRate', '缺少有效体验者或全款人数');
  }
  final rate = numerator / denominator;
  final highPriceCount = aggregate.localProPaymentsAtOrAbove79;
  final status = rate >=
              CommerceExperimentThresholds.localProFullContinueRate &&
          numerator >= CommerceExperimentThresholds.localProFullContinueCount &&
          highPriceCount != null &&
          highPriceCount >=
              CommerceExperimentThresholds.localProHighPriceContinueCount
      ? CommerceDecisionStatus.continueLine
      : rate < CommerceExperimentThresholds.localProFullAdjustRate ||
              numerator <
                  CommerceExperimentThresholds.localProFullAdjustMinimumCount
          ? CommerceDecisionStatus.stopLine
          : CommerceDecisionStatus.adjustLine;
  return CommerceMetricDecision(
    key: 'localProFullPaymentRate',
    status: status,
    numerator: numerator,
    denominator: denominator,
    rate: rate,
    reason: highPriceCount == null
        ? '缺少 79 元以上支付人数，不能判定继续线'
        : 'Local Pro 全款率 ${(rate * 100).toStringAsFixed(2)}%，全款 $numerator 人，79 元以上 $highPriceCount 人',
  );
}

CommerceMetricDecision _d7Decision(CommerceExperimentAggregate aggregate) =>
    _ratioDecision(
      key: 'd7ReturnRate',
      numerator: aggregate.d7ReturningUsers,
      denominator: aggregate.validExperienceUsers,
      continueRate: CommerceExperimentThresholds.d7ReturnContinueRate,
      adjustRate: CommerceExperimentThresholds.d7ReturnAdjustRate,
      label: '七日回访率',
    );

CommerceMetricDecision _realmDecision(
  CommerceExperimentAggregate aggregate,
) =>
    _ratioDecision(
      key: 'realmFullPaymentRate',
      numerator: aggregate.realmFullPayments,
      denominator: aggregate.completeRealmPreviews,
      continueRate: CommerceExperimentThresholds.realmPurchaseContinueRate,
      adjustRate: CommerceExperimentThresholds.realmPurchaseAdjustRate,
      label: '书境包全款率',
    );

CommerceMetricDecision _xiaoyoReasonDecision(
  CommerceExperimentAggregate aggregate,
) {
  final decision = _ratioDecision(
    key: 'xiaoyoTop3ReasonRate',
    numerator: aggregate.xiaoyoTop3ReasonUsers,
    denominator: aggregate.paidInterviewUsers,
    continueRate: CommerceExperimentThresholds.xiaoyoReasonContinueRate,
    adjustRate: CommerceExperimentThresholds.xiaoyoReasonAdjustRate,
    label: 'Xiaoyo 前三付费理由比例',
  );
  if (decision.status == CommerceDecisionStatus.insufficientEvidence) {
    return decision;
  }
  if (decision.status != CommerceDecisionStatus.continueLine ||
      decision.numerator == null ||
      decision.numerator! <
          CommerceExperimentThresholds.xiaoyoReasonContinueCount) {
    return decision.status == CommerceDecisionStatus.stopLine
        ? decision
        : CommerceMetricDecision(
            key: decision.key,
            status: CommerceDecisionStatus.adjustLine,
            numerator: decision.numerator,
            denominator: decision.denominator,
            rate: decision.rate,
            reason: '比例或最少 3 名付款后访谈用户未同时达到继续线',
          );
  }
  return decision;
}

CommerceMetricDecision _authorDecision(
  CommerceExperimentAggregate aggregate,
) {
  final decision = _ratioDecision(
    key: 'authorFullPaymentRate',
    numerator: aggregate.authorFullPayments,
    denominator: aggregate.qualifiedAuthorExperiencers,
    continueRate: CommerceExperimentThresholds.authorPurchaseContinueRate,
    adjustRate: CommerceExperimentThresholds.authorPurchaseAdjustRate,
    label: '作者听校全款率',
  );
  if (decision.status == CommerceDecisionStatus.insufficientEvidence) {
    return decision;
  }
  if (decision.numerator == 0 ||
      decision.rate! < CommerceExperimentThresholds.authorPurchaseAdjustRate) {
    return CommerceMetricDecision(
      key: decision.key,
      status: CommerceDecisionStatus.stopLine,
      numerator: decision.numerator,
      denominator: decision.denominator,
      rate: decision.rate,
      reason: '作者听校无支付或全款率低于 5%',
    );
  }
  if (decision.numerator! <
      CommerceExperimentThresholds.authorPurchaseContinueCount) {
    return CommerceMetricDecision(
      key: decision.key,
      status: CommerceDecisionStatus.adjustLine,
      numerator: decision.numerator,
      denominator: decision.denominator,
      rate: decision.rate,
      reason: '有支付但不足 2 笔，保持调整线',
    );
  }
  return decision;
}

CommerceMetricDecision _cloudTtsDecision(
  CommerceExperimentAggregate aggregate,
) {
  final evidence = aggregate.cloudTts;
  if (evidence == null ||
      evidence.licensed == null ||
      evidence.privacyApproved == null ||
      evidence.grossMarginPercent == null ||
      evidence.unitEconomicsFailed == null) {
    return _insufficient('cloudTts', '缺少持牌、隐私、毛利或单位经济证据');
  }
  if (!evidence.licensed! || !evidence.privacyApproved!) {
    return const CommerceMetricDecision(
      key: 'cloudTts',
      status: CommerceDecisionStatus.stopLine,
      numerator: null,
      denominator: null,
      rate: null,
      reason: '持牌或隐私合规未通过',
    );
  }
  if (evidence.unitEconomicsFailed!) {
    return const CommerceMetricDecision(
      key: 'cloudTts',
      status: CommerceDecisionStatus.stopLine,
      numerator: null,
      denominator: null,
      rate: null,
      reason: '单位经济已确认失败',
    );
  }
  final marginRate = evidence.grossMarginPercent! / 100;
  return CommerceMetricDecision(
    key: 'cloudTts',
    status: marginRate >=
            CommerceExperimentThresholds.cloudTtsGrossMarginContinueRate
        ? CommerceDecisionStatus.continueLine
        : CommerceDecisionStatus.adjustLine,
    numerator: null,
    denominator: null,
    rate: marginRate,
    reason: marginRate >=
            CommerceExperimentThresholds.cloudTtsGrossMarginContinueRate
        ? '持牌、隐私和目标毛利均达到继续线'
        : '仅成本偏高，需调整供应商或单位经济',
  );
}

CommerceMetricDecision _ratioDecision({
  required String key,
  required int? numerator,
  required int? denominator,
  required double continueRate,
  required double adjustRate,
  required String label,
}) {
  if (numerator == null || denominator == null || denominator <= 0) {
    return _insufficient(key, '缺少 $label 分子或分母');
  }
  final rate = numerator / denominator;
  final status = rate >= continueRate
      ? CommerceDecisionStatus.continueLine
      : rate >= adjustRate
          ? CommerceDecisionStatus.adjustLine
          : CommerceDecisionStatus.stopLine;
  return CommerceMetricDecision(
    key: key,
    status: status,
    numerator: numerator,
    denominator: denominator,
    rate: rate,
    reason: '$label ${(rate * 100).toStringAsFixed(2)}%',
  );
}

CommerceMetricDecision _insufficient(String key, String reason) =>
    CommerceMetricDecision(
      key: key,
      status: CommerceDecisionStatus.insufficientEvidence,
      numerator: null,
      denominator: null,
      rate: null,
      reason: reason,
    );

void _validateAtMost(int? numerator, int? denominator, String key) {
  if (numerator != null && denominator != null && numerator > denominator) {
    throw FormatException('$key 不能大于对应分母');
  }
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) throw FormatException('$key 必须是布尔值或 null');
  return value;
}

int? _optionalNonNegativeInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw FormatException('$key 必须是非负整数或 null');
  }
  return value;
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('$key 必须是非负数字或 null');
  }
  return value.toDouble();
}

const _forbiddenKeys = <String>{
  'userId',
  'accountId',
  'phone',
  'email',
  'deviceId',
  'bookTitle',
  'content',
  'path',
  'chapterText',
  'cursor',
  'ttsText',
};

void _rejectPrivateFields(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is String && _forbiddenKeys.contains(entry.key)) {
        throw FormatException('聚合实验数据禁止包含字段：${entry.key}');
      }
      _rejectPrivateFields(entry.value);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      _rejectPrivateFields(item);
    }
  }
}
