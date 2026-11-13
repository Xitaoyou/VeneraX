import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app_update.dart';
import 'package:venera/foundation/guide_document.dart';

void main() {
  test('fork release keeps upstream and personal change sections separate', () {
    final blocks = parseAppChangelog('''
# VeneraX 2.3.12+10030
## 上游更新（中文）
本次是同一上游版本的重新构建。
### 新增
- 上游设置功能
## 个人修改（本 Fork）
以下功能持续保留，并非本次全部新增。
### 阅读与返回手势
- 个人下滑返回
''');
    final headings = blocks
        .where(isChangelogHeading)
        .map((b) => b.text)
        .toList();
    expect(
      headings,
      containsAllInOrder(['上游更新（中文）', '新增', '个人修改（本 Fork）', '阅读与返回手势']),
    );
    expect(
      blocks.where((b) => b.type == GuideBlockType.bullet).map((b) => b.text),
      ['上游设置功能', '个人下滑返回'],
    );
  });

}
