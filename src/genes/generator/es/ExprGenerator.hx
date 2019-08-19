package genes.generator.es;

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.Context;
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
    return node(e, read(ctx -> switch (e.expr) {
      case TConst(c): constant(c);
      case TLocal(v): ident(v.name);
      case TArray(e1, e2):
        [value(addObjectdeclParens(e1)), '[', value(e2), ']'];
      case TBinop(op, {expr: TField(x, f)}, e2) if (fieldName(f) == 'iterator'):
        [value(x), field('iterator'), ' ', binop(op), ' ', value(e2)];
      case TBinop(op, e1, e2):
        [value(e1), ' ', binop(op), ' ', value(e2)];
      case TField(x, f) if (fieldName(f) == "iterator" && isDynamicIterator(ctx, e)):
        ctx.addFeature("use.$iterator");
        ["$iterator(", value(x), ")"];
      case TUnop(op, postFix, fe = {expr: TField(x, f)}) if (fieldName(f) == 'iterator' && isDynamicIterator(ctx, fe)):
        switch postFix {
          case false:
            [unop(op), value(x), '.iterator'];
          case true:
            [value(x), '.iterator', unop(op)];
        }
      /*
        case TField(x, FClosure(Some({c:{cl_path:{a:[], b:"Array"}}}), {cf_name:"push"})):
          // see https://github.com/HaxeFoundation/haxe/issues/1997
          add_feature(ctx, "use.$arrayPush");
          add_feature(ctx, "use.$bind");
          print(ctx, "$bind(");
          gen_value(ctx, x);
          print(ctx, ",$arrayPush");
       */
      case TField(x, FClosure(_, _.get() => {name: name})):
        switch (x.expr) {
          case TConst(_) | TLocal(_):
            [value(x), field(name), '.bind(', value(x), ')'];
          case _:
            // Todo: figure out this mess, also take care of selfCall
            [value(x), field(name), '.bind(', value(x), ')'];
        }
      case TEnumIndex(x):
        [value(x), "._hx_index"];
      case TEnumParameter(x, f, i):
        var fname = switch f.type {
          case TFun(args, _): args[i].name;
          case _: throw 'assert';
        }
          [value(x), field(fname)];
      case TField(_, FStatic(_.get() => {
        pack: [],
        name: ''
      }, _.get().name => fname)):
        fname;
      case TField(x, FInstance(_, _, _.get() => f) | FStatic(_, _.get() => f) | FAnon(_.get() => f)) if (f.meta.has(':selfCall')):
        value(x);
      case TField(x, f):
        function skip(e: TypedExpr): TypedExpr
          return switch e.expr {
            case TCast(e1, null) | TMeta(_, e1): skip(e1);
            case TConst(TInt(_) | TFloat(_)) | TObjectDecl(_): parenthesis(e);
            case _: e;
          }
            [
              value(skip(x)),
              switch f {
                case FStatic(_.get() => c, _):
                  staticField(c, fieldName(f));
                case FEnum(_), FInstance(_), FAnon(_), FDynamic(_), FClosure(_):
                  field(fieldName(f));
              }
            ];
      case TTypeExpr(t):
        ctx.typeAccessor(t);
      case TParenthesis(e1):
        ['(', value(e1), ')'];
      case TMeta({name: ':loopLabel', params: [{expr: EConst(CInt(n))}]}, e):
        switch (e.expr) {
          case TWhile(_, _, _), TFor(_, _, _):
            ['_hx_loop${n}: ', expr(e)];
          case TBreak:
            'break _hx_loop${n}';
          case _: throw 'assert';
        }
      case TMeta(_, e):
        expr(e);
      case TReturn(e):
        switch e {
          case null: 'return';
          case eo: node(e, 'return ', node(eo, value(eo)));
        }
      case TBreak:
        if (!ctx.inLoop) throw 'Unsupported';
        'break';
      case TContinue:
        if (!ctx.inLoop) throw 'Unsupported';
        'continue';
      case TBlock(el):
        [
          '{',
          write(ctx -> {tabs: ctx.tabs + '\t'}, el.map(e -> blockElement(e))),
          newline,
          '}'
        ];
      case TFunction(f):
        write(ctx -> {inValue: 0, inLoop: false},
          ['function (', join(f.args.map(a -> ident(a.v.name)), ', '), ') ', expr(f.expr)]);
      case TCall({expr: TField(_, FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: 'code'}))},
        _) | TCall({expr: TIdent('__js__')}, _):
        return read(ctx -> ctx.expr(e));
      case TCall(e, params):
        call(e, params, false);
      case TArrayDecl(el):
        ['[', join(el.map(value), ', '), ']'];
      case TThrow(e):
        ['throw ', value(e)];
      case TVar(v, eo):
        [
          'var ',
          ident(v.name),
          switch (eo) {
            case null:
              '';
            case e:
              [' = ', value(e)];
          }
        ];
      /*
        case TNew({cl_path:{a:[], b:"Array"}}, _, []):
          print(ctx, "[]");
       */
      case TNew(c, _, el):
        [
          switch (c.get().constructor) {
            case null:
              'new ';
            case _.get() => cf if (cf.meta.has(':selfCall')):
              '';
            default:
              'new ';
          },
          ctx.typeAccessor(TClassDecl(c)),
          '(',
          join(el.map(value), ', '),
          ')'
        ];
      case TIf(cond, e, eelse):
        [
          'if ',
          value(cond),
          ' ',
          expr(block(e)),
          switch eelse {
            case null:
              '';
            case e2:
              [
                ' else ',
                expr(switch e2.expr {
                  case TIf(_, _, _): e2;
                  case _: block(e2);
                })
              ];
          }
        ];
      case TUnop(op, false, e):
        [unop(op), value(e)];
      case TUnop(op, true, e):
        [value(e), unop(op)];
      case TWhile(cond, e, true):
        write(ctx -> {inLoop: true}, ['while ', value(cond), ' ', expr(e)]);
      case TWhile(cond, e, false):
        write(ctx -> {inLoop: true}, ['do ', expr(e), '; while ', value(cond)]);
      case TObjectDecl(fields):
        [
          '{',
          join(fields.map(field -> node(field.expr, ['"${field.name}": ', value(field.expr)])),
            ', '),
          '}'
        ];
      case TFor(v, it, e):
        write(ctx -> {inLoop: true}, {
          var init: SourceNode = [];
          final it = ident(switch it.expr {
            case TLocal(v): v.name;
            case _:
              final id = ctx.idCounter;
              ctx.idCounter++;
              final name = "$it" + id;
              init = ['var ${name} = ', value(it), newline];
              name;
          });
          [
            init,
            'while (${it}.hasNext()) {',
            indent([newline, 'var ${ident(v.name)} = ${it}.next()', blockElement(e)]),
            newline,
            '}'
          ];
        });
      case TTry(etry, [{v: v, expr: ecatch}]):
        [
                         'try ', expr(etry),
          ' catch (${v.name}) ', expr(ecatch)
        ];
      case TTry(_):
        throw 'Unhandled try/catch, please report';
      case TSwitch(cond, cases, def):
        genSwitch(cond, cases, def, v -> v);
      case TCast(e, null):
        expr(e);
      /*      case TCast(e1, t):
        print(ctx, '${ctx.type_accessor(TClassDecl(core.Type.null_class.with({cl_path:{a:["js"], b:"Boot"}})))}.__cast(');
        gen_expr(ctx, e1);
        spr(ctx, " , ");
        spr(ctx, ctx.type_accessor(t));
        spr(ctx, ")");
       */
      case TIdent("$hxEnums"): hxEnums;
      case TIdent(s): s;
      default:
        [];
    }));

  public static final hxEnums = {
    final key = "$hxEnums";
    final global = '(typeof window!=="undefined"?window:global)';
    '((g,k)=>g[k]||(g[k]={}))($global,"$key")';
  }

  public static function ident(name: String): SourceNode
    return if (keywords.indexOf(name) > -1) "$" + name else name;

  static function staticField(c: ClassType, s: String): String
    return switch s {
      case 'length' | 'name' if (!c.isExtern || c.meta.has(':hxGen')): ".$" + s;
      case s: field(s);
    }

  static function field(name: String): String // Todo: check valid js ident
    return if (keywords.indexOf(name) > -1) '["${name}"]' else '.${name}';

  static function asValue(assigner: (assign: SourceNode->SourceNode)->
    SourceNode): SourceNode
    return read(ctx -> {
      final id = ctx.inValue + 1;
      function assign(e: SourceNode): SourceNode
        return ['$$r$id = ', e];
      return [
        write(ctx -> {inValue: id, inLoop: false}, [
          "(function($this) {",
          indent(['var $$r$id', newline, assigner(assign), newline, 'return $$r$id']),
          '})'
        ]),
        '(',
        this_,
        ')'
      ];
    });

  public static function value(e: TypedExpr): SourceNode
    return node(e, switch (e.expr) {
      case TMeta(_, e1):
        value(e1);
      case TCall({expr: TField(_, FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: 'code'}))},
        _) | TCall({expr: TIdent('__js__')}, _):
        return read(ctx -> ctx.value(e));
      case TCall(e, params):
        call(e, params, true);
      case TReturn(_) | TBreak | TContinue:
        throw 'Unsupported $e';
      case TCast(e1, null):
        value(e1);
      /*case TCast(e1, t):
        print(ctx, '${ctx.type_accessor(TClassDecl(core.Type.null_class.with({cl_path:{a:["js"], b:"Boot"}})))}.__cast(');
        gen_value(ctx, e1);
        spr(ctx, " , ");
        spr(ctx, (ctx.type_accessor(t)));
        spr(ctx, ")"); */
      case TVar(_), TFor(_, _, _), TWhile(_, _, _), TThrow(_):
        asValue(assign -> assign(expr(e))); // todo: value
      case TBlock([]):
        'null';
      case TBlock([e]):
        value(e);
      case TBlock(el):
        asValue(assign -> [
          join(el.slice(0, el.length - 1).map(expr), newline),
          newline,
          assign(value(el[el.length - 1]))
        ]);
      case TIf(cond, e, eo): [
          value(cond),
          ' ? ',
          value(e),
          ' : ',
          switch eo {
            case null:
              'null';
            case e:
              value(e);
          }
        ];
      case TSwitch(cond, cases, def):
        asValue(assign -> genSwitch(cond, cases, def, assign));
      case TTry(etry, [{v: v, expr: ecatch}]):
        asValue(assign ->
          ['try {', assign(value(etry)), '} catch (${v.name}) ', assign(value(ecatch))]);
      default: expr(e);
    });

  static function genSwitch(cond: TypedExpr,
      cases: Array<{values: Array<TypedExpr>, expr: TypedExpr}>,
      def: Null<TypedExpr>, leaf: (n: SourceNode) -> SourceNode): SourceNode
    return [
      'switch ',
      value(cond),
      ' {',
      indent([
        newline,
        cases.map(c -> node(c.expr, c.values.map(e -> node(e, switch e.expr {
          case TConst(TNull):
            'case null: case undefined:';
          default:
            ['case ', value(e), ': '];
        })), indent([
            leaf(blockElement(c.expr)),
            newline,
            'break' // Todo: implement needs_switch_break
          ]), newline)),
        switch def {
          case null:
            [];
          case e:
            node(e, 'default:', indent(leaf(blockElement(e))), newline);
        }
      ]),
      newline,
      '}'
    ];

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
    return if (context.inValue == 0) 'this' else "$this";

  public static function unop(op: Unop): String
    return switch (op) {
      case OpIncrement: "++";
      case OpDecrement: "--";
      case OpNot: "!";
      case OpNeg: "-";
      case OpNegBits: "~";
    }

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

  static function addObjectdeclParens(e: TypedExpr): TypedExpr {
    function loop(e: TypedExpr): TypedExpr
      return switch (e.expr) {
        case TCast(e1, null), TMeta(_, e1): loop(e1);
        case TObjectDecl(_): parenthesis(e);
        case _: e;
      }
    return loop(e);
  }

  static function posInfo(fields: Array<{name: String, expr: TypedExpr}>)
    return switch [fields[0], fields[1]] {
      case [
        {name: 'fileName', expr: {expr: TConst(TString(file))}},
        {name: 'lineNumber', expr: {expr: TConst(TInt(line))}}
      ]:
        {file: file, line: line}
      case _: null;
    }

  static function call(e: TypedExpr, params: Array<TypedExpr>,
      inValue: Bool): SourceNode
    return node(e, read(ctx -> switch [e.expr, params] {
      case [TIdent('`trace'), [e, info]]:
        [
          'console.log(',
          switch info.expr {
            case TObjectDecl(posInfo(_) => info) if (info != null):
              '"${info.file}:${info.line}:",';
            case _:
              '';
          },
          value(e),
          ')'
        ];
      case [TCall(x, _), el] if (switch (x.expr) {
          case TIdent('__js__'): false;
          case _: true;
        }):
        ['(', value(e), ')(', join(el.map(value), ', '), ')'];
      case [
        TField(_, FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: name})),
        args
      ]:
        syntax(name, args);
      case [TIdent("__new__"), args]:
        syntax("new_", args);
      case [TIdent("__instanceof__"), args]:
        syntax("instanceof", args);
      case [TIdent("__typeof__"), args]:
        syntax("typeof", args);
      case [TIdent("__strict_eq__"), args]:
        syntax("strictEq", args);
      case [TIdent("__strict_neq__"), args]:
        syntax("strictNeq", args);
      case [TIdent('__define_feature__'), [_, e]]:
        expr(e);
      case [TIdent('__feature__'), [{expr: TConst(TString(f))}, eif]]:
        read(ctx -> if (ctx.hasFeature(f)) value(eif) else []);
      case [TIdent('__feature__'), [{expr: TConst(TString(f))}, eif, eelse]]:
        read(ctx -> if (ctx.hasFeature(f)) value(eif) else value(eelse));
      case [TField(x, f), []] if (fieldName(f) == "iterator" && isDynamicIterator(ctx, e)):
        ctx.addFeature("use.$getIterator");
        ['(o=>Array.isArray(o)?HxOverrides.iter(o):o.iterator())(', value(x), ')'];
      default:
        [value(e), '(', join(params.map(value), ', '), ')'];
    }));

  static function syntax(method: String, args: Array<TypedExpr>): SourceNode
    return switch method {
      case 'construct':
        ['new ', value(args[0]), '(', join(args.slice(1).map(value), ', '), ')'];
      case 'instanceof':
        ['((', value(args[0]), ') instanceof ', value(args[1]), ')'];
      case 'typeof':
        ['typeof(', value(args[0]), ')'];
      case 'strictEq':
        ['((', value(args[0]), ') === (', value(args[1]), '))'];
      case 'strictNeq':
        ['((', value(args[0]), ') !== (', value(args[1]), '))'];
      case 'delete':
        ['delete(', value(args[0]), '[', value(args[1]), '])'];
      case 'field':
        [value(args[0]), '[', value(args[1]), '])'];
      default:
        throw 'Unknown js.Syntax method "$method"';
    }

  public static function blockElement(e: TypedExpr, after = false)
    return node(e, switch e.expr {
      case TBlock(el):
        el.map(blockElement.bind(_, after));
      case TCall({expr: TIdent('__feature__')}, [{expr: TConst(TString(f))}, eif]):
        read(ctx -> if (ctx.hasFeature(f)) blockElement(eif) else []);
      case TCall({expr: TIdent('__feature__')}, [{expr: TConst(TString(f))}, eif, eelse]):
        read(ctx -> if (ctx.hasFeature(f)) blockElement(eif, after) else
          blockElement(eelse, after));
      case TFunction(_):
        blockElement(parenthesis(e), after);
      case TObjectDecl(fl):
        fl.map(field -> blockElement(field.expr, after));
      case _:
        if (!after) [newline, expr(e), ';'] else [expr(e), newline];
    });

  public static function isDynamicIterator(ctx: Context, e: TypedExpr): Bool
    return switch e.expr {
      case TField(x, f) if (fieldName(f) == "iterator" && ctx.hasFeature('HxOverrides.iter')):
        switch haxe.macro.Context.followWithAbstracts(x.t) {
          case TInst(_.get() => {name: 'Array'}, _) | TInst(_.get() => {kind: KTypeParameter(_)}, _) | TAnonymous(_) | TDynamic(_) | TMono(_):
            true;
          case _:
            false;
        }
      case _:
        false;
    }

  static function parenthesis(e: TypedExpr): TypedExpr
    return {expr: TParenthesis(e), t: e.t, pos: e.pos}

  static function block(e: TypedExpr): TypedExpr
    return switch e.expr {
      case TBlock(_): e;
      case _: {expr: TBlock([e]), t: e.t, pos: e.pos}
    }

  public static function fieldName(f: FieldAccess): String
    return switch f {
      case FAnon(f), FInstance(_, _, f), FStatic(_, f), FClosure(_, f):
        f.get().name;
      case FEnum(_, f): f.name;
      case FDynamic(n): n;
    }

  public static function stringEscape(?hex = true, s: String): String {
    var b = new StringBuf();
    for (i in 0...s.length) {
      var c = s.charAt(i);
      switch c {
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
