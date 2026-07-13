import 'package:flutter_test/flutter_test.dart';

enum _G1EventType {
  importCompleted,
  readingStarted,
  sentenceSpoken,
  interruption,
  resumed,
  networkDegraded,
  retrySucceeded,
  unrecoverableFailure,
  playbackStopped,
  exited,
}

class _G1Event {
  const _G1Event(this.type, {this.sentenceId});

  final _G1EventType type;
  final String? sentenceId;
}

class _G1Scenario {
  const _G1Scenario({
    required this.id,
    required this.events,
    required this.listenSeconds,
  });

  final String id;
  final List<_G1Event> events;
  final int listenSeconds;
}

class _G1ScenarioResult {
  const _G1ScenarioResult({required this.id, required this.issues});

  final String id;
  final List<String> issues;

  bool get passed => issues.isEmpty;
}

class _G1SimulationReport {
  const _G1SimulationReport(this.results);

  final List<_G1ScenarioResult> results;

  int get passedCount => results.where((_G1ScenarioResult item) => item.passed).length;

  bool get engineeringGatePassed =>
      results.length == 5 && passedCount == results.length;
}

_G1SimulationReport _runG1Simulation(List<_G1Scenario> scenarios) {
  return _G1SimulationReport(
    scenarios.map(_evaluateG1Scenario).toList(growable: false),
  );
}

_G1ScenarioResult _evaluateG1Scenario(_G1Scenario scenario) {
  final issues = <String>[];
  final spokenSentences = <String>[];
  var imported = false;
  var reading = false;
  var interrupted = false;
  var recoveredAfterInterruption = false;
  var exitedCleanly = false;
  var networkRecovered = true;

  for (final event in scenario.events) {
    switch (event.type) {
      case _G1EventType.importCompleted:
        imported = true;
      case _G1EventType.readingStarted:
        if (!imported) {
          issues.add('未导入书籍就开始朗读');
        }
        reading = true;
      case _G1EventType.sentenceSpoken:
        if (!reading) {
          issues.add('未处于朗读状态却播报句子');
        }
        final sentenceId = event.sentenceId;
        if (sentenceId == null) {
          issues.add('句子事件缺少编号');
          continue;
        }
        if (spokenSentences.contains(sentenceId)) {
          issues.add('出现重复句: $sentenceId');
        }
        if (spokenSentences.isNotEmpty &&
            !_isSequential(spokenSentences.last, sentenceId)) {
          issues.add('出现跳句: ${spokenSentences.last} -> $sentenceId');
        }
        spokenSentences.add(sentenceId);
      case _G1EventType.interruption:
        if (!reading) {
          issues.add('非朗读状态收到中断');
        }
        reading = false;
        interrupted = true;
      case _G1EventType.resumed:
        if (!interrupted) {
          issues.add('没有中断却执行恢复');
        }
        reading = true;
        recoveredAfterInterruption = true;
      case _G1EventType.networkDegraded:
        networkRecovered = false;
      case _G1EventType.retrySucceeded:
        networkRecovered = true;
      case _G1EventType.unrecoverableFailure:
        issues.add('出现不可恢复中断');
        reading = false;
      case _G1EventType.playbackStopped:
        reading = false;
      case _G1EventType.exited:
        if (reading) {
          issues.add('退出时仍残留朗读');
        }
        exitedCleanly = true;
    }
  }

  if (!imported) {
    issues.add('导入未完成');
  }
  if (scenario.listenSeconds < 600) {
    issues.add('有效听读不足 10 分钟');
  }
  if (interrupted && !recoveredAfterInterruption) {
    issues.add('中断后未恢复');
  }
  if (!networkRecovered) {
    issues.add('弱网后未恢复');
  }
  if (!exitedCleanly) {
    issues.add('未验证退出路径');
  }

  return _G1ScenarioResult(id: scenario.id, issues: issues);
}

bool _isSequential(String previous, String current) {
  final previousNumber = int.tryParse(previous.substring(1));
  final currentNumber = int.tryParse(current.substring(1));
  return previousNumber != null &&
      currentNumber != null &&
      currentNumber == previousNumber + 1;
}

_G1Event _import() => const _G1Event(_G1EventType.importCompleted);

_G1Event _start() => const _G1Event(_G1EventType.readingStarted);

_G1Event _sentence(int number) =>
    _G1Event(_G1EventType.sentenceSpoken, sentenceId: 's$number');

_G1Event _stop() => const _G1Event(_G1EventType.playbackStopped);

final _g1Scenarios = <_G1Scenario>[
  _G1Scenario(
    id: 'S01',
    listenSeconds: 600,
    events: <_G1Event>[
      _import(),
      _start(),
      _sentence(1),
      _sentence(2),
      _sentence(3),
      _stop(),
      const _G1Event(_G1EventType.exited),
    ],
  ),
  _G1Scenario(
    id: 'S02',
    listenSeconds: 600,
    events: <_G1Event>[
      _import(),
      _start(),
      _sentence(1),
      const _G1Event(_G1EventType.interruption),
      const _G1Event(_G1EventType.resumed),
      _sentence(2),
      _stop(),
      const _G1Event(_G1EventType.exited),
    ],
  ),
  _G1Scenario(
    id: 'S03',
    listenSeconds: 600,
    events: <_G1Event>[
      _import(),
      _start(),
      _sentence(1),
      _sentence(2),
      _sentence(3),
      _sentence(4),
      _stop(),
      const _G1Event(_G1EventType.exited),
    ],
  ),
  _G1Scenario(
    id: 'S04',
    listenSeconds: 600,
    events: <_G1Event>[
      _import(),
      _start(),
      _sentence(1),
      _stop(),
      const _G1Event(_G1EventType.exited),
    ],
  ),
  _G1Scenario(
    id: 'S05',
    listenSeconds: 600,
    events: <_G1Event>[
      _import(),
      _start(),
      _sentence(1),
      const _G1Event(_G1EventType.networkDegraded),
      const _G1Event(_G1EventType.retrySucceeded),
      _sentence(2),
      _stop(),
      const _G1Event(_G1EventType.exited),
    ],
  ),
];

void main() {
  test('G1 五组正常造数场景全部通过工程验证门', () {
    final report = _runG1Simulation(_g1Scenarios);

    expect(report.results.map((_G1ScenarioResult item) => item.id), <String>[
      'S01',
      'S02',
      'S03',
      'S04',
      'S05',
    ]);
    expect(report.passedCount, 5);
    expect(report.engineeringGatePassed, isTrue);
  });

  test('G1 门禁拒绝重复句、跳句和不可恢复中断', () {
    final invalidScenario = _G1Scenario(
      id: 'INVALID',
      listenSeconds: 600,
      events: <_G1Event>[
        _import(),
        _start(),
        _sentence(1),
        _sentence(1),
        _sentence(3),
        const _G1Event(_G1EventType.unrecoverableFailure),
        const _G1Event(_G1EventType.exited),
      ],
    );
    final result = _runG1Simulation(<_G1Scenario>[invalidScenario]).results.single;

    expect(result.passed, isFalse);
    expect(result.issues, contains('出现重复句: s1'));
    expect(result.issues, contains('出现跳句: s1 -> s3'));
    expect(result.issues, contains('出现不可恢复中断'));
    expect(_runG1Simulation(<_G1Scenario>[invalidScenario]).engineeringGatePassed, isFalse);
  });
}
