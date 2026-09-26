import 'package:flutter_test/flutter_test.dart';
import 'package:pictureviewer/state/app_state.dart';

/// 回归用例：TAG 面板的「清除此标签筛选」。
///
/// 旧实现连调 toggleAndFilter / toggleOrFilter / toggleNotFilter 三次，
/// 后一个 toggle 会把前一个刚移除的标签重新加进另一个集合，
/// 终态固定变成「排除该标签」。这三个集合的运算现在由 [TagFilter] 承担。
void main() {
  group('TagFilter.withoutTag', () {
    test('一次从 AND / OR / NOT 三处移除同一个标签', () {
      const f = TagFilter(andTagIds: [1, 2], orTagIds: [1, 3], notTagIds: [1, 4]);
      final r = f.withoutTag(1);
      expect(r.andTagIds, [2]);
      expect(r.orTagIds, [3]);
      expect(r.notTagIds, [4]);
      expect(r.active, isTrue);
    });

    test('只参与 NOT 的标签也能一次清干净', () {
      // 旧实现：toggleAndFilter 把 7 加进 and，再被后面两个 toggle 挪走，
      // 最终停在 not=[7]，按钮点了等于「排除该标签」。
      const f = TagFilter(notTagIds: [7]);
      final r = f.withoutTag(7);
      expect(r.active, isFalse);
      expect(r.andTagIds, isEmpty);
      expect(r.orTagIds, isEmpty);
      expect(r.notTagIds, isEmpty);
    });

    test('未参与的标签不改变任何集合', () {
      const f = TagFilter(andTagIds: [1], orTagIds: [2], notTagIds: [3]);
      final r = f.withoutTag(9);
      expect(r.andTagIds, [1]);
      expect(r.orTagIds, [2]);
      expect(r.notTagIds, [3]);
    });

    test('清空后 active 为 false，其余标签保留', () {
      const f = TagFilter(andTagIds: [5]);
      final r = f.withoutTag(5);
      expect(r.active, isFalse);
    });
  });

  group('TagFilter.contains', () {
    test('三个集合都算命中', () {
      const f = TagFilter(andTagIds: [1], orTagIds: [2], notTagIds: [3]);
      expect(f.contains(1), isTrue);
      expect(f.contains(2), isTrue);
      expect(f.contains(3), isTrue);
      expect(f.contains(4), isFalse);
    });
  });
}
