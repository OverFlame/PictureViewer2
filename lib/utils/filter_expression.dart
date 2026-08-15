/// 高级筛选布尔表达式解析与 SQL 编译。
///
/// 支持语法：
/// - 标签引用：`风景`、`地点:风景`（命名空间:名称），或 `"带 空格 名字"`（引号内按名称匹配）
/// - 运算符：`!`（非）、`&&`/`&`（与）、`||`/`|`（或）
/// - 优先级：`!` > `&&` > `||`，括号 `()` 改变优先级
///
/// 示例：`((A||B)&&!C)||C`

/// 表达式语法错误
class FilterExpressionException implements Exception {
  final String message;

  /// 0 起始的错误位置（字符索引）
  final int position;

  const FilterExpressionException(this.message, this.position);

  @override
  String toString() => position >= 0 ? '$message（第 ${position + 1} 个字符附近）' : message;
}

/// 表达式抽象语法树节点
sealed class Expr {
  const Expr();
}

/// 标签引用（未解析：保留原始文本，查询时再解析为 tag id）
class TagRef extends Expr {
  final String text;

  /// 是否来自引号（引号内按名称精确匹配，不解析命名空间）
  final bool quoted;

  const TagRef(this.text, {this.quoted = false});
}

class NotExpr extends Expr {
  final Expr child;
  const NotExpr(this.child);
}

class AndExpr extends Expr {
  final Expr left;
  final Expr right;
  const AndExpr(this.left, this.right);
}

class OrExpr extends Expr {
  final Expr left;
  final Expr right;
  const OrExpr(this.left, this.right);
}

/// 表达式解析器
class FilterExpressionParser {
  FilterExpressionParser._();

  /// 解析表达式为 AST；语法错误抛出 [FilterExpressionException]
  static Expr parse(String input) {
    final tokens = _tokenize(input);
    if (tokens.length == 1) {
      // 只有 EOF，空输入
      throw const FilterExpressionException('表达式为空', 0);
    }
    return _Parser(tokens).parse();
  }
}

// ═══════════════════ 词法分析 ═══════════════════

enum _T { ident, lparen, rparen, and_, or_, not_, eof }

class _Tok {
  final _T type;
  final String text;
  final bool quoted;
  final int pos;

  const _Tok(this.type, this.pos, {this.text = '', this.quoted = false});
}

List<_Tok> _tokenize(String input) {
  final tokens = <_Tok>[];
  int i = 0;

  while (i < input.length) {
    final c = input[i];

    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i++;
      continue;
    }
    if (c == '(') {
      tokens.add(_Tok(_T.lparen, i));
      i++;
      continue;
    }
    if (c == ')') {
      tokens.add(_Tok(_T.rparen, i));
      i++;
      continue;
    }
    if (c == '&') {
      final isDouble = i + 1 < input.length && input[i + 1] == '&';
      tokens.add(_Tok(_T.and_, i));
      i += isDouble ? 2 : 1;
      continue;
    }
    if (c == '|') {
      final isDouble = i + 1 < input.length && input[i + 1] == '|';
      tokens.add(_Tok(_T.or_, i));
      i += isDouble ? 2 : 1;
      continue;
    }
    if (c == '!') {
      tokens.add(_Tok(_T.not_, i));
      i++;
      continue;
    }
    if (c == '"' || c == "'") {
      final quote = c;
      final start = i;
      i++;
      final buf = StringBuffer();
      while (i < input.length && input[i] != quote) {
        buf.write(input[i]);
        i++;
      }
      if (i >= input.length) {
        throw FilterExpressionException('引号未闭合', start);
      }
      i++; // 跳过闭合引号
      tokens.add(_Tok(_T.ident, start, text: buf.toString(), quoted: true));
      continue;
    }

    // 普通标识符：读到空白 / 运算符 / 括号 / 引号为止
    final start = i;
    final buf = StringBuffer();
    while (i < input.length) {
      final ch = input[i];
      if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' ||
          ch == '(' || ch == ')' || ch == '&' || ch == '|' || ch == '!' ||
          ch == '"' || ch == "'") {
        break;
      }
      buf.write(ch);
      i++;
    }
    tokens.add(_Tok(_T.ident, start, text: buf.toString()));
  }

  tokens.add(_Tok(_T.eof, input.length));
  return tokens;
}

// ═══════════════════ 语法分析 ═══════════════════

class _Parser {
  final List<_Tok> _ts;
  int _i = 0;

  _Parser(this._ts);

  _Tok get _cur => _ts[_i];

  Expr parse() {
    final e = _parseOr();
    if (_cur.type != _T.eof) {
      throw FilterExpressionException(
          '此处出现多余内容「${_describe(_cur)}」', _cur.pos);
    }
    return e;
  }

  // or  := and ( '||' and )*
  Expr _parseOr() {
    var left = _parseAnd();
    while (_cur.type == _T.or_) {
      _i++;
      final right = _parseAnd();
      left = OrExpr(left, right);
    }
    return left;
  }

  // and := not ( '&&' not )*
  Expr _parseAnd() {
    var left = _parseNot();
    while (_cur.type == _T.and_) {
      _i++;
      final right = _parseNot();
      left = AndExpr(left, right);
    }
    return left;
  }

  // not := '!' not | primary
  Expr _parseNot() {
    if (_cur.type == _T.not_) {
      _i++;
      return NotExpr(_parseNot());
    }
    return _parsePrimary();
  }

  // primary := '(' or ')' | ident
  Expr _parsePrimary() {
    final t = _cur;
    if (t.type == _T.lparen) {
      _i++;
      final e = _parseOr();
      if (_cur.type != _T.rparen) {
        throw FilterExpressionException('缺少右括号「)」', _cur.pos);
      }
      _i++;
      return e;
    }
    if (t.type == _T.ident) {
      _i++;
      return TagRef(t.text, quoted: t.quoted);
    }
    if (t.type == _T.eof) {
      throw FilterExpressionException('表达式不完整', t.pos);
    }
    throw FilterExpressionException(
        '此处需要标签名或「(」，却遇到「${_describe(t)}」', t.pos);
  }

  String _describe(_Tok t) => switch (t.type) {
        _T.lparen => '(',
        _T.rparen => ')',
        _T.and_ => '&&',
        _T.or_ => '||',
        _T.not_ => '!',
        _T.eof => '（结尾）',
        _T.ident => t.text,
      };
}

// ═══════════════════ SQL 编译 ═══════════════════

/// 将 AST 编译为返回 image_id 集合的 SQL 子查询。
///
/// [resolve] 负责把 [TagRef] 解析为 tag id 列表（空列表表示该原子恒假）。
/// 用 SQLite 的 INTERSECT / UNION / EXCEPT 直接组合集合运算。
String buildImageIdSubquery(Expr ast, List<int> Function(TagRef ref) resolve) {
  if (ast is TagRef) {
    return _tagRefSql(resolve(ast));
  } else if (ast is NotExpr) {
    return '(SELECT id FROM images) EXCEPT (${buildImageIdSubquery(ast.child, resolve)})';
  } else if (ast is AndExpr) {
    return '(${buildImageIdSubquery(ast.left, resolve)}) INTERSECT '
        '(${buildImageIdSubquery(ast.right, resolve)})';
  } else if (ast is OrExpr) {
    return '(${buildImageIdSubquery(ast.left, resolve)}) UNION '
        '(${buildImageIdSubquery(ast.right, resolve)})';
  }
  throw StateError('未知的表达式节点类型');
}

String _tagRefSql(List<int> ids) {
  if (ids.isEmpty) {
    return 'SELECT image_id FROM image_tags WHERE 0';
  }
  return 'SELECT image_id FROM image_tags WHERE tag_id IN (${ids.join(',')})';
}
