import 'package:flutter_test/flutter_test.dart';
import 'package:pictureviewer/utils/filter_expression.dart';

/// 用一个可变引用接住异常，方便断言消息与位置
FilterExpressionException? _caught(String input) {
  try {
    FilterExpressionParser.parse(input);
  } on FilterExpressionException catch (e) {
    return e;
  }
  return null;
}

void main() {
  group('正常解析', () {
    test('括号、取反与引号标签的浅层组合', () {
      final ast = FilterExpressionParser.parse('!(a && b) || "c d"');
      expect(ast, isA<OrExpr>());
    });

    test('50 层括号在深度上限之内', () {
      final input = '${'(' * 50}a${')' * 50}';
      expect(FilterExpressionParser.parse(input), isA<TagRef>());
    });

    test('200 个取反在上限之内', () {
      final ast = FilterExpressionParser.parse('${'!' * 200}a');
      expect(ast, isA<NotExpr>());
    });

    test('两万项 && 的宽表达式能解析（解析器按循环处理，不看宽度）', () {
      final ast =
          FilterExpressionParser.parse(List.filled(20000, 'a').join(' && '));
      expect(ast, isA<AndExpr>());
    });
  });

  group('嵌套深度上限', () {
    test('5000 层括号抛 FilterExpressionException，不再是 StackOverflowError',
        () {
      final input = '${'(' * 5000}a${')' * 5000}';
      expect(
        () => FilterExpressionParser.parse(input),
        throwsA(isA<FilterExpressionException>()),
      );
      expect(_caught(input)!.message, contains('嵌套过深'));
    });

    test('5000 个连续取反同样被拦住', () {
      final input = '${'!' * 5000}a';
      expect(
        () => FilterExpressionParser.parse(input),
        throwsA(isA<FilterExpressionException>()),
      );
      expect(_caught(input)!.message, contains('嵌套过深'));
    });

    test('400 层括号已经越界', () {
      final input = '${'(' * 400}a${')' * 400}';
      expect(_caught(input), isNotNull);
    });
  });

  group('浅层非法输入仍然给带位置的中文提示', () {
    final cases = <String, String>{
      '((((1': '缺少右括号',
      'a &&&& b': '需要标签名',
      'a |||': '需要标签名',
      '!!!': '表达式不完整',
      '(': '表达式不完整',
      '"abc': '引号未闭合',
      'a)': '多余内容',
      '': '表达式为空',
      '   ': '表达式为空',
    };

    cases.forEach((input, expected) {
      test('「$input」提示 $expected', () {
        final e = _caught(input);
        expect(e, isNotNull, reason: '「$input」应当报错');
        expect(e!.message, contains(expected));
      });
    });
  });

  group('SQL 编译', () {
    test('简单表达式的形状', () {
      final ast = FilterExpressionParser.parse('a && !b');
      final sql = buildImageIdSubquery(
        ast,
        (ref) => [ref.text == 'a' ? 1 : 2],
      );
      expect(
        sql,
        '(SELECT image_id FROM image_tags WHERE tag_id IN (1)) INTERSECT '
        '((SELECT id FROM images) EXCEPT '
        '(SELECT image_id FROM image_tags WHERE tag_id IN (2)))',
      );
    });

    test('解析不出的标签名编译成恒假', () {
      final ast = FilterExpressionParser.parse('a && b');
      final sql = buildImageIdSubquery(ast, (ref) => const <int>[]);
      expect(sql, contains('WHERE 0'));
    });

    test('宽表达式编译不递归爆栈', () {
      // 左边深树：递归实现会按树深吃栈帧，这里走到显式栈
      final ast =
          FilterExpressionParser.parse(List.filled(2000, 'a').join(' && '));
      final sql = buildImageIdSubquery(ast, (ref) => const [7]);
      expect(sql, contains('INTERSECT'));
      expect(sql, contains('tag_id IN (7)'));
    });
  });
}
