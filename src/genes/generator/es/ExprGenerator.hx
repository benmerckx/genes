package genes.generator.es;

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.PositionTools.toLocation;
import genes.SourceNode;
import genes.SourceNode.*;

class ExprGenerator {
  static final keywords = [
    'abstract', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class',
    'const', 'continue', 'debugger', 'default', 'delete', 'do', 'double',
    'else', 'enum', 'export', 'extends', 'false', 'final', 'finally', 'float',
    'for', 'function', 'goto', 'if', 'implements', 'import', 'in',
    'instanceof', 'int', 'interface', 'long', 'native', 'new', 'null',
    'package', 'private', 'protected', 'public', 'return', 'short', 'static',
    'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient',
    'true', 'try', 'typeof', 'var', 'void', 'volatile', 'while', 'with',
    'arguments', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'debugger', 'default', 'delete', 'do', 'else', 'enum', 'eval', 'export',
    'extends', 'false', 'finally', 'for', 'function', 'if', 'implements',
    'import', 'in', 'instanceof', 'interface', 'let', 'new', 'null',
    'package', 'private', 'protected', 'public', 'return', 'static', 'super',
    'switch', 'this', 'throw', 'true', 'try', 'typeof', 'var', 'void',
    'while', 'with', 'yield'
  ];

  public static function expr(e: TypedExpr): SourceNode
    return node(e, switch (e.expr) {
      case TConst(c): constant(c);
      case TLocal(v): ident(v.name);
      case TArray(e1, e2): [
        value(e1), '[', value(e2), ']'
      ]; // Todo: add parens
      // Todo: binop iterator (...)
      case TBinop(op, e1, e2): [
        value(e1), ' ${binop(op)} ', value(e2)
      ];
      // Todo: bunch of stuff
      case TFunction(f): write(ctx -> {inValue: false, inLoop: false}, [
        'function (', f.args.map(a -> ident(a.v.name)), ') ',
        expr(f.expr)
      ]);
      case TVar(v, eo): [
        'var ', ident(v.name),
        switch (eo) {
          case null: '';
          case e: [' = ', value(e)];
        }
      ];
      case TBlock(el): [
        '{', 
          write(ctx -> {tabs: ctx.tabs + '\t'},
            el.map(e -> blockElement(e))
          ),
          newline,
        '}',
      ];
      case TParenthesis(e1): [
        '(', expr(e1), ')'
      ];
      case TReturn(e):
        switch e {
          case null: node(e, 'return');
          case eo: node(e, 'return ', node(eo, value(eo)));
        }
      // ...
      case TCall(e, el): call(e, el, false);
      case TIdent(s): s;
      default:
        [];
    });

  public static function ident(name: String): SourceNode
    return if (keywords.indexOf(name) > -1) "$" + name else name;

  public static function value(e: TypedExpr): SourceNode
    return node(e, switch (e.expr) {
      case TConst(_), TLocal(_), TArray(_, _), TBinop(_, _, _), TField(_,_), 
        TEnumParameter(_, _), TEnumIndex(_), TTypeExpr(_), TParenthesis(_), 
        TObjectDecl(_), TArrayDecl(_), TNew(_, _, _), TUnop(_, _, _), 
        TFunction(_), TIdent(_):
        expr(e);
      case TMeta(_, e1):
        value(e1);
      case TCall(e, el):
        call(e, el, true);
      case TReturn(_), TBreak, TContinue:
        throw 'Unsupported';
      case TCast(e1, _):
        value(e1); // todo: some case
      case TVar(_), TFor(_, _, _), TWhile(_, _, _), TThrow(_):
        expr(e); // todo: value
      case TBlock([e]):
        value(e);
      case TIf(cond, e, eo): [
        value(cond), ' ? ', value(e), ' : ',
        switch eo {
          case null:
            'null';
          case e:
            value(e);
        }
      ];
      default: expr(e);
    });

  public static function constant(c: TConstant): SourceNode
    return switch (c) {
      case TInt(i): '${i}';
      case TFloat(s): '${s}';
      case TString(s): '"${stringEscape(s)}"';
      case TBool(b): if (b) 'true' else 'false';
      case TNull: 'null';
      case TThis: this_;
      case TSuper: 'super';
    }

  static function this_(context: Context): SourceNode
    return if (context.inValue) 'this' else "$this";

  public static function binop(op: Binop): SourceNode
    return switch (op) {
      case OpAdd: '+';
      case OpMult: '*';
      case OpDiv: '/';
      case OpSub: '-';
      case OpAssign: '=';
      case OpEq: '==';
      case OpNotEq: '!=';
      case OpGte: '>=';
      case OpLte: '<=';
      case OpGt: '>';
      case OpLt: '<';
      case OpAnd: '&';
      case OpOr: '|';
      case OpXor: '^';
      case OpBoolAnd: '&&';
      case OpBoolOr: '||';
      case OpShr: '>>';
      case OpUShr: '>>>';
      case OpShl: '<<';
      case OpMod: '%';
      case OpAssignOp(op): binop(op) + '=';
      case OpInterval: '...';
      case OpArrow: '=>';
      case OpIn: ' in ';
    }

  static final newline = read(ctx -> '\n${ctx.tabs}');

  static function posInfo(fields: Array<{name:String, expr:TypedExpr}>)
    return switch [fields[0], fields[1]] {
      case [{name: 'fileName', expr: {expr: TConst(TString(file))}},
            {name: 'lineNumber', expr: {expr: TConst(TInt(line))}}]:
        {file: file, line: line}
      case _: null;
    }

  public static function call(e: TypedExpr, params: Array<TypedExpr>,
      inValue: Bool): SourceNode
    return node(e, switch [e.expr, params] {
      case [TIdent('`trace'), [e, info]]:
        [
          'console.log(',
            switch info.expr {
              case TObjectDecl(posInfo(_) => info) if (info != null): 
                '"${info.file}:${info.line}:",';
              case _: '';
            },
            value(e),
          ')'
        ];
      default:
        [value(e), '(', join(params.map(value), ', '), ')'];
    });

  public static function blockElement(e: TypedExpr, after = false)
    return node(e, switch (e.expr) {
      case TBlock(el):
        el.map(blockElement.bind(_, after));
      case TCall({expr:TIdent('__feature__')}, [{expr:TConst(TString(f))}, eif, eelse]): // Todo: match more eelse
        read(ctx ->
          if (ctx.hasFeature(f))
            blockElement(eif, after)
          else
            blockElement(eelse, after)
        );
      case TFunction(_):
        blockElement({expr: TParenthesis(e), t: e.t, pos: e.pos}, after);
      case TObjectDecl(fl):
        fl.map(field -> blockElement(field.expr, after));
      case _ :
        if (!after) [newline, expr(e)]
        else [expr(e), newline];
    });

  public static function stringEscape(?hex = true, s: String): String {
    var b = new StringBuf();
    for (i in 0...s.length) {
      var c = s.charAt(i);
      switch (c) {
        case '\n':
          b.add("\\n");
        case '\t':
          b.add("\\t");
        case '\r':
          b.add("\\r");
        case '"':
          b.add("\\\"");
        case '\\':
          b.add("\\\\");
        default:
          var ci = c.charCodeAt(0);
          b.add((ci < 32 && hex) ? "\\x" + StringTools.hex(ci) : c);
      }
    }
    return b.toString();
  }
}
