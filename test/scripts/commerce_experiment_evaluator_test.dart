import 'package:flutter_test/flutter_test.dart';

import '../../scripts/commerce_experiment_evaluator.dart';

CommerceExperimentAggregate _aggregate({
  bool? paymentChannelVerified = true,
  bool? refundDrillVerified = true,
  bool? ownerApproved = true,
  int? qualifiedVisitors = 100,
  int? localProDeposits = 3,
  int? validExperienceUsers = 40,
  int? localProFullPayments = 6,
  int? localProPaymentsAtOrAbove79 = 3,
  int? d7ReturningUsers = 14,
  int? completeRealmPreviews = 40,
  int? realmFullPayments = 6,
  int? paidInterviewUsers = 10,
  int? xiaoyoTop3ReasonUsers = 4,
  int? qualifiedAuthorExperiencers = 20,
  int? authorFullPayments = 2,
  CloudTtsEvidence? cloudTts,
}) {
  return CommerceExperimentAggregate(
    paymentChannelVerified: paymentChannelVerified,
    refundDrillVerified: refundDrillVerified,
    ownerApproved: ownerApproved,
    qualifiedVisitors: qualifiedVisitors,
    localProDeposits: localProDeposits,
    validExperienceUsers: validExperienceUsers,
    localProFullPayments: localProFullPayments,
    localProPaymentsAtOrAbove79: localProPaymentsAtOrAbove79,
    d7ReturningUsers: d7ReturningUsers,
    completeRealmPreviews: completeRealmPreviews,
    realmFullPayments: realmFullPayments,
    paidInterviewUsers: paidInterviewUsers,
    xiaoyoTop3ReasonUsers: xiaoyoTop3ReasonUsers,
    qualifiedAuthorExperiencers: qualifiedAuthorExperiencers,
    authorFullPayments: authorFullPayments,
    grossPaidFen: 20000,
    refundedFen: 1000,
    cloudTts: cloudTts ??
        const CloudTtsEvidence(
          licensed: true,
          privacyApproved: true,
          grossMarginPercent: 65,
          unitEconomicsFailed: false,
        ),
  );
}

void main() {
  test('前置条件未通过时即使指标很好也只能判定未启动', () {
    final report = evaluateCommerceExperiment(
      _aggregate(paymentChannelVerified: false),
    );

    expect(report.status, CommerceDecisionStatus.notStarted);
  });

  test('所有指标达到继续线时输出继续线并计算净支付', () {
    final report = evaluateCommerceExperiment(_aggregate());

    expect(report.status, CommerceDecisionStatus.continueLine);
    expect(report.netPaidFen, 19000);
    expect(report.decisions, hasLength(7));
  });

  test('缺少实验前置条件或指标时输出证据不足', () {
    final report = evaluateCommerceExperiment(
      _aggregate(
        ownerApproved: null,
        d7ReturningUsers: null,
        xiaoyoTop3ReasonUsers: null,
      ),
    );

    expect(report.status, CommerceDecisionStatus.insufficientEvidence);
    expect(
      report.decisions
          .firstWhere((decision) => decision.key == 'd7ReturnRate')
          .status,
      CommerceDecisionStatus.insufficientEvidence,
    );
    expect(
      report.decisions
          .firstWhere((decision) => decision.key == 'xiaoyoTop3ReasonRate')
          .status,
      CommerceDecisionStatus.insufficientEvidence,
    );
  });

  test('Local Pro 与书境包同时停止时触发普通用户总停止线', () {
    final report = evaluateCommerceExperiment(
      _aggregate(
        localProDeposits: 0,
        localProFullPayments: 2,
        localProPaymentsAtOrAbove79: 0,
        realmFullPayments: 0,
      ),
    );

    expect(report.status, CommerceDecisionStatus.stopLine);
  });

  test('Xiaoyo 比例达到但访谈人数不足三人时只能调整', () {
    final report = evaluateCommerceExperiment(
      _aggregate(paidInterviewUsers: 2, xiaoyoTop3ReasonUsers: 2),
    );

    final decision = report.decisions
        .firstWhere((item) => item.key == 'xiaoyoTop3ReasonRate');
    expect(decision.status, CommerceDecisionStatus.adjustLine);
  });

  test('作者听校有一笔支付时进入调整线，零支付进入停止线', () {
    final adjusted = evaluateCommerceExperiment(
      _aggregate(authorFullPayments: 1),
    );
    final stopped = evaluateCommerceExperiment(
      _aggregate(authorFullPayments: 0),
    );

    expect(
      adjusted.decisions
          .firstWhere((item) => item.key == 'authorFullPaymentRate')
          .status,
      CommerceDecisionStatus.adjustLine,
    );
    expect(
      stopped.decisions
          .firstWhere((item) => item.key == 'authorFullPaymentRate')
          .status,
      CommerceDecisionStatus.stopLine,
    );
  });

  test('云音色合规失败停止，单纯毛利偏低调整', () {
    final complianceStopped = evaluateCommerceExperiment(
      _aggregate(
        cloudTts: const CloudTtsEvidence(
          licensed: false,
          privacyApproved: true,
          grossMarginPercent: 65,
          unitEconomicsFailed: false,
        ),
      ),
    );
    final costAdjusted = evaluateCommerceExperiment(
      _aggregate(
        cloudTts: const CloudTtsEvidence(
          licensed: true,
          privacyApproved: true,
          grossMarginPercent: 40,
          unitEconomicsFailed: false,
        ),
      ),
    );

    expect(
      complianceStopped.decisions
          .firstWhere((item) => item.key == 'cloudTts')
          .status,
      CommerceDecisionStatus.stopLine,
    );
    expect(
      costAdjusted.decisions
          .firstWhere((item) => item.key == 'cloudTts')
          .status,
      CommerceDecisionStatus.adjustLine,
    );
  });

  test('拒绝正文、路径和账号字段，拒绝计数超过分母', () {
    expect(
      () => CommerceExperimentAggregate.fromJson({
        'bookTitle': '不应出现',
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CommerceExperimentAggregate.fromJson({
        'localProDeposits': 2,
        'qualifiedVisitors': 1,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('退款金额不能超过总支付金额', () {
    expect(
      () => CommerceExperimentAggregate.fromJson({
        'grossPaidFen': 100,
        'refundedFen': 101,
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
