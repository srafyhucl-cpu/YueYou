import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yueyou/features/xiaoyo/domain/xiaoyo_profile.dart';
import 'package:yueyou/features/xiaoyo/providers/xiaoyo_profile_notifier.dart';
import 'package:yueyou/features/xiaoyo/presentation/widgets/xiaoyo_profile_transfer_actions.dart';
import 'package:yueyou/features/xiaoyo/services/xiaoyo_profile_transfer_service.dart';

void main() {
  testWidgets('数据转移操作展示导出和恢复两个可取消入口', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          xiaoyoProfileTransferServiceProvider.overrideWithValue(
            XiaoyoProfileTransferService(
              filePicker: _FakeTransferPicker(),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: XiaoyoProfileTransferActions(
              profile: XiaoyoProfile.empty(
                nowUtc: DateTime.utc(2026, 7, 14),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('导出成长数据'), findsOneWidget);
    expect(find.text('恢复成长数据'), findsOneWidget);
    expect(find.byIcon(Icons.upload_file_outlined), findsOneWidget);
    expect(find.byIcon(Icons.file_open_outlined), findsOneWidget);
  });
}

final class _FakeTransferPicker implements XiaoyoProfileTransferFilePicker {
  @override
  Future<String?> saveJson({
    required String fileName,
    required String content,
  }) async =>
      null;

  @override
  Future<String?> readJson() async => null;
}
