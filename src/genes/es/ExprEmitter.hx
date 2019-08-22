package genes.es;

import haxe.macro.Expr;
import haxe.macro.Type;
import genes.util.TypeUtil.*;
import genes.util.IteratorUtil.*;

using haxe.macro.TypedExprTools;

class ExprEmitter extends Emitter {
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

  var indent: Int = 0;
  var inValue: Int = 0;
  var idCounter: Int = 0;
  var inLoop: Bool = false;

  public function emitExpr(e: TypedExpr) {
    emitPos(e.pos);
    switch e.expr {
      case TConst(c):
        emitConstant(c);
      case TLocal(v):
        emitIdent(v.name);
      case TArray(e1, e2):
        emitValue(addObjectdeclParens(e1));
        write('[');
        emitValue(e2);
        write(']');
      case TBinop(op, {expr: TField(x, f)}, e2) if (fieldName(f) == 'iterator'):
        emitValue(x);
        emitField('iterator');
        writeSpace();
        writeBinop(op);
        writeSpace();
        emitValue(e2);
      case TBinop(op, e1, e2):
        emitValue(e1);
        writeSpace();
        writeBinop(op);
        writeSpace();
        emitValue(e2);
      case TField(x, f) if (fieldName(f) == "iterator" && isDynamicIterator(ctx, e)):
        ctx.addFeature("use.$iterator");
        write("$iterator(");
        emitValue(x);
        write(")");
      case TUnop(op, postFix, fe = {expr: TField(x, f)}) if (fieldName(f) == 'iterator' && isDynamicIterator(ctx, fe)):
        switch postFix {
          case false:
            writeUnop(op);
            emitValue(x);
            write('.iterator');
          case true:
            emitValue(x);
            write('.iterator');
            writeUnop(op);
        }
      /*
        case TField(x, FClosure(Some({c:{cl_path:{a:[], b:"Array"}}}), {cf_name:"push"})):
          // see https://github.com/HaxeFoundation/haxe/issues/1997
          add_feature(ctx, "use.$arrayPush");
          add_feature(ctx, "use.$bind");
          print(ctx, "$bind(");
          gen_emitValue(ctx, x);
          print(ctx, ",$arrayPush");
       */
      case TField(x, FClosure(_, _.get() => {name: name})):
        switch (x.expr) {
          case TConst(_) | TLocal(_):
            emitValue(x);
            emitField(name);
            write('.bind(');
            emitValue(x);
            write(')');
          case _:
            // Todo: figure out this mess, also take care of selfCall
            write('(o=>o');
            emitField(name);
            write('.bind(o))(');
            emitValue(x);
            write(')');
        }
      case TEnumIndex(x):
        emitValue(x);
        write("._hx_index");
      case TEnumParameter(x, f, i):
        emitValue(x);
        emitField(switch f.type {
          case TFun(args, _): args[i].name;
          case _: throw 'assert';
        });
      case TField(_, FStatic(_.get() => {
        pack: [],
        name: ''
      }, _.get().name => fname)):
        write(fname);
      case TField(x, FInstance(_, _, _.get() => f) | FStatic(_, _.get() => f) | FAnon(_.get() => f)) if (f.meta.has(':selfCall')):
        emitValue(x);
      case TField(x, f):
        function skip(e: TypedExpr): TypedExpr
          return switch e.expr {
            case TCast(e1, null) | TMeta(_, e1): skip(e1);
            case TConst(TInt(_) | TFloat(_)) | TObjectDecl(_): with(e, TParenthesis(e));
            case _: e;
          }
        emitValue(skip(x));
        switch f {
          case FStatic(_.get() => c, _):
            emitStaticField(c, fieldName(f));
          case FEnum(_), FInstance(_), FAnon(_), FDynamic(_), FClosure(_):
            emitField(fieldName(f));
        }
      case TTypeExpr(t):
        write(ctx.typeAccessor(t));
      case TParenthesis(e1):
        write('(');
        emitValue(e1);
        write(')');
      case TMeta({name: ':loopLabel', params: [{expr: EConst(CInt(n))}]}, e):
        switch (e.expr) {
          case TWhile(_, _, _), TFor(_, _, _):
            write('_hx_loop${n}: ');
            emitExpr(e);
          case TBreak:
            write('break _hx_loop${n}');
          case _: throw 'assert';
        }
      case TMeta(_, e):
        emitExpr(e);
      case TReturn(e):
        switch e {
          case null: write('return');
          case eo:
            emitPos(e.pos);
            write('return ');
            emitValue(eo);
        }
      case TBreak:
        if (!inLoop)
          throw 'Unsupported';
        write('break');
      case TContinue:
        if (!inLoop)
          throw 'Unsupported';
        write('continue');
      case TBlock(el):
        write('{');
        increaseIndent();
        for (e in el)
          emitBlockElement(e);
        decreaseIndent();
        writeNewline();
        write('}');
      case TFunction(f):
        final inValue = this.inValue;
        final inLoop = this.inLoop;
        this.inValue = 0;
        this.inLoop = false;
        write('function (');
        for (arg in join(f.args, write.bind(', ')))
          emitIdent(arg.v.name);
        write(') ');
        emitExpr(f.expr);
        this.inValue = inValue;
        this.inLoop = inLoop;
      case TCall({expr: TField(_, FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: 'code'}))},
        _) | TCall({expr: TIdent('__js__')}, _):
        write(ctx.expr(e));
      case TCall(e, params):
        emitCall(e, params, false);
      case TArrayDecl(el):
        write('[');
        for (e in join(el, write.bind(', ')))
          emitValue(e);
        write(']');
      case TThrow(e):
        write('throw ');
        emitValue(e);
      case TVar(v, eo):
        write('var ');
        emitIdent(v.name);
        switch (eo) {
          case null:
          case e:
            write(' = ');
            emitValue(e);
        }
      case TNew(c, _, el):
        write(switch (c.get().constructor) {
          case null:
            'new ';
          case _.get() => cf if (cf.meta.has(':selfCall')):
            '';
          default:
            'new ';
        });
        write(ctx.typeAccessor(TClassDecl(c)));
        write('(');
        for (e in join(el, write.bind(', ')))
          emitValue(e);
        write(')');
      case TIf(cond, e, eelse):
        write('if ');
        emitValue(cond);
        writeSpace();
        emitExpr(block(e));
        switch eelse {
          case null:
          case e2:
            emitPos(e2.pos);
            write(' else ');
            emitExpr(switch e2.expr {
              case TIf(_, _, _): e2;
              case _: block(e2);
            });
        }
      case TUnop(op, false, e):
        writeUnop(op);
        emitValue(e);
      case TUnop(op, true, e):
        emitValue(e);
        writeUnop(op);
      case TWhile(cond, e, true):
        final inLoop = this.inLoop;
        this.inLoop = true;
        write('while ');
        emitValue(cond);
        writeSpace();
        emitExpr(e);
        this.inLoop = inLoop;
      case TWhile(cond, e, false):
        final inLoop = this.inLoop;
        this.inLoop = true;
        write('do ');
        emitExpr(e);
        write('; while ');
        emitValue(cond);
        this.inLoop = inLoop;
      case TObjectDecl(fields):
        write('{');
        for (field in join(fields, write.bind(', '))) {
          emitPos(field.expr.pos);
          emitString(field.name);
          write(': ');
          emitValue(field.expr);
        }
        write('}');
      case TFor(v, it, e):
        final inLoop = this.inLoop;
        this.inLoop = true;
        final it = switch it.expr {
          case TLocal(v): v.name;
          case _:
            final id = idCounter;
            idCounter++;
            final name = "$it" + id;
            write('var ${name} = ');
            emitValue(it);
            writeNewline();
            name;
        }
        write('while (');
        emitIdent(it);
        write('.hasNext()) {');
        increaseIndent();
        writeNewline();
        write('var ');
        emitIdent(v.name);
        write(' = ');
        emitIdent(it);
        write('.next()');
        writeNewline();
        emitBlockElement(e);
        decreaseIndent();
        writeNewline();
        write('}');
        this.inLoop = inLoop;
      case TTry(etry, [{v: v, expr: ecatch}]):
        write('try ');
        emitExpr(etry);
        write('catch (');
        emitIdent(v.name);
        write(') ');
        emitExpr(ecatch);
      case TTry(_):
        throw 'Unhandled try/catch, please report';
      case TSwitch(cond, cases, def):
        emitSwitch(cond, cases, def, e -> emitBlockElement(e));
      case TCast(e, null):
        emitExpr(e);
      /*      case TCast(e1, t):
        print(ctx, '${ctx.type_accessor(TClassDecl(core.Type.null_class.with({cl_path:{a:["js"], b:"Boot"}})))}.__cast(');
        gen_emitExpr(ctx, e1);
        spr(ctx, " , ");
        spr(ctx, ctx.type_accessor(t));
        spr(ctx, ")");
       */
      case TIdent("$hxEnums"):
        writehxEnums();
      case TIdent(s):
        write(s);
      default:
    }
  }

  function emitCall(e: TypedExpr, params: Array<TypedExpr>, inValue: Bool) {
    emitPos(e.pos);
    switch [e.expr, params] {
      case [TIdent('`trace'), [e, info]]:
        write('console.log(');
        switch info.expr {
          case TObjectDecl(posInfo(_) => info) if (info != null):
            write('"${info.file}:${info.line}:",');
          default:
        }
        emitValue(e);
        write(')');
      case [TCall(x, _), el] if (switch (x.expr) {
          case TIdent('__js__'): false;
          case _: true;
        }):
        write('(');
        emitValue(e);
        write(')(');
        for (e in join(el, write.bind(', ')))
          emitValue(e);
        write(')');
      case [
        TField(_, FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: name})),
        args
      ]:
        emitSyntax(name, args);
      case [TIdent("__new__"), args]:
        emitSyntax("new_", args);
      case [TIdent("__instanceof__"), args]:
        emitSyntax("instanceof", args);
      case [TIdent("__typeof__"), args]:
        emitSyntax("typeof", args);
      case [TIdent("__strict_eq__"), args]:
        emitSyntax("strictEq", args);
      case [TIdent("__strict_neq__"), args]:
        emitSyntax("strictNeq", args);
      case [TIdent('__define_feature__'), [_, e]]:
        emitExpr(e);
      case [TIdent('__feature__'), [{expr: TConst(TString(f))}, eif]]:
        if (ctx.hasFeature(f))
          emitValue(eif);
      case [TIdent('__feature__'), [{expr: TConst(TString(f))}, eif, eelse]]:
        if (ctx.hasFeature(f))
          emitValue(eif)
        else
          emitValue(eelse);
      case [TField(x, f), []] if (fieldName(f) == "iterator" && isDynamicIterator(ctx, e)):
        ctx.addFeature("use.$getIterator");
        write('(o=>Array.isArray(o)?HxOverrides.iter(o):o.iterator())(');
        emitValue(x);
        write(')');
      default:
        emitValue(e);
        write('(');
        for (param in join(params, write.bind(', ')))
          emitValue(param);
        write(')');
    }
  }

  function emitSyntax(method: String, args: Array<TypedExpr>)
    switch method {
      case 'construct':
        write('new ');
        emitValue(args[0]);
        write('(');
        for (arg in join(args.slice(1), write.bind(', ')))
          emitValue(arg);
        write(')');
      case 'instanceof':
        write('((');
        emitValue(args[0]);
        write(') instanceof ');
        emitValue(args[1]);
        write(')');
      case 'typeof':
        write('typeof(');
        emitValue(args[0]);
        write(')');
      case 'strictEq':
        write('((');
        emitValue(args[0]);
        write(') === (');
        emitValue(args[1]);
        write('))');
      case 'strictNeq':
        write('((');
        emitValue(args[0]);
        write(') !== (');
        emitValue(args[1]);
        write('))');
      case 'delete':
        write('delete(');
        emitValue(args[0]);
        write('[');
        emitValue(args[1]);
        write('])');
      case 'field':
        emitValue(args[0]);
        write('[');
        emitValue(args[1]);
        write('])');
      default:
        throw 'Unknown js.Syntax method "$method"';
    }

  function asValue(assigner: (assign: TypedExpr->Void)->Void) {
    final inValue = this.inValue;
    final inLoop = this.inLoop;
    final id = this.inValue++;
    this.inLoop = false;
    function assign(e: TypedExpr) {
      write('$$r$id = ');
      emitValue(e);
    }
    write("(function($this) {");
    increaseIndent();
    write('var $$r$id');
    writeNewline();
    assigner(assign);
    writeNewline();
    write('return $$r$id');
    decreaseIndent();
    write('})');
    this.inValue = inValue;
    this.inLoop = inLoop;
    write('(');
    emitThis();
    write(')');
  }

  function emitValue(e: TypedExpr) {
    emitPos(e.pos);
    switch e.expr {
      case TMeta(_, e1):
        emitValue(e1);
      case TCall({expr: TField(_, FStatic(_.get() => {module: 'js.Syntax'}, _.get() => {name: 'code'}))},
        _) | TCall({expr: TIdent('__js__')}, _):
        write(ctx.value(e));
      case TCall(e, params):
        emitCall(e, params, true);
      case TReturn(_) | TBreak | TContinue:
        throw 'Unsupported $e';
      case TCast(e1, null):
        emitValue(e1);
      /*case TCast(e1, t):
        print(ctx, '${ctx.type_accessor(TClassDecl(core.Type.null_class.with({cl_path:{a:["js"], b:"Boot"}})))}.__cast(');
        gen_value(ctx, e1);
        spr(ctx, " , ");
        spr(ctx, (ctx.type_accessor(t)));
        spr(ctx, ")"); */
      case TVar(_), TFor(_, _, _), TWhile(_, _, _), TThrow(_):
        asValue(assign -> assign(e));
      case TBlock([]): // Todo: hm?
        write('null');
      case TBlock([e]):
        emitValue(e);
      case TBlock(el):
        asValue(assign -> {
          for (e in el.slice(0, el.length - 1)) {
            emitExpr(e);
            writeNewline();
          }
          writeNewline();
          assign(el[el.length - 1]);
        });
      case TIf(cond, e, eo):
        emitValue(cond);
        write(' ? ');
        emitValue(e);
        write(' : ');
        switch eo {
          case null:
            write('null');
          case e:
            emitValue(e);
        }
      case TSwitch(cond, cases, def):
        asValue(assign -> {
          emitSwitch(cond, cases, def, assign);
        });
      case TTry(etry, [{v: v, expr: ecatch}]):
        asValue(assign -> {
          write('try {');
          assign(block(etry));
          write('} catch (');
          emitIdent(v.name);
          write(') {');
          assign(block(ecatch));
          write(') {');
        });
      default:
        emitExpr(e);
    }
  }

  function emitSwitch(cond: TypedExpr,
      cases: Array<{values: Array<TypedExpr>, expr: TypedExpr}>,
      def: Null<TypedExpr>, leaf: TypedExpr->Void) {
    write('switch ');
    emitValue(cond);
    write(' {');
    increaseIndent();
    writeNewline();
    for (c in cases) {
      emitPos(c.expr.pos);
      for (v in c.values) {
        emitPos(v.pos);
        switch v.expr {
          case TConst(TNull):
            write('case null: case undefined:');
          default:
            write('case ');
            emitValue(v);
            write(':');
        }
      }
      increaseIndent();
      leaf(c.expr);
      writeNewline();
      write('break'); // Todo: implement needs_switch_break
      writeNewline();
    }
    switch def {
      case null:
      case e:
        emitPos(e.pos);
        write('default:');
        leaf(e);
        writeNewline();
    }
    writeNewline();
    write('}');
  }

  public function emitConstant(c: TConstant)
    switch (c) {
      case TInt(i):
        write('${i}');
      case TFloat(s):
        write('${s}');
      case TString(s):
        emitString(s);
      case TBool(b):
        write(if (b) 'true' else 'false');
      case TNull:
        write('null');
      case TThis:
        emitThis();
      case TSuper:
        write('super');
    }

  function emitThis() {
    if (inValue == 0)
      write('this')
    else
      write("$this");
  }

  function emitBlockElement(e: TypedExpr, after = false) {
    emitPos(e.pos);
    switch e.expr {
      case TBlock(el):
        for (e in el)
          emitBlockElement(e, after);
      case TCall({expr: TIdent('__feature__')}, [{expr: TConst(TString(f))}, eif]):
        if (ctx.hasFeature(f))
          emitBlockElement(eif, after);
      case TCall({expr: TIdent('__feature__')}, [{expr: TConst(TString(f))}, eif, eelse]):
        if (ctx.hasFeature(f))
          emitBlockElement(eif, after)
        else
          emitBlockElement(eelse, after);
      case TFunction(_):
        emitBlockElement(with(e, TParenthesis(e)), after);
      case TObjectDecl(fl):
        for (field in fl)
          emitBlockElement(field.expr, after);
      case _:
        if (!after)
          writeNewline();
        emitExpr(e);
        write(';');
        if (after)
          writeNewline();
    }
  }

  function emitString(input: String) {
    writeQuotes();
    for (char in input)
      write(switch char {
        case '\n'.code: "\\n";
        case '\t'.code: "\\t";
        case '\r'.code: "\\r";
        case '"'.code: "\\\"";
        case '\\'.code: "\\\\";
        case code:
          if (code < 32) "\\x" + StringTools.hex(code, 2) else
            String.fromCharCode(code);
      });
    writeQuotes();
  }

  function emitFieldName(f: FieldAccess) {
    write(fieldName(f));
  }

  function emitIdent(name: String) {
    if (keywords.indexOf(name) > -1)
      write("$");
    write(name);
  }

  function emitStaticField(c: ClassType, s: String)
    return switch s {
      case 'length' | 'name' if (!c.isExtern || c.meta.has(':hxGen')):
        write(".$" + s);
      case s: emitField(s);
    }

  function emitField(name: String) {
    if (keywords.indexOf(name) > -1)
      write('["${name}"]')
    else
      write('.${name}');
  }

  public function writeUnop(op: Unop)
    write(switch (op) {
      case OpIncrement: "++";
      case OpDecrement: "--";
      case OpNot: "!";
      case OpNeg: "-";
      case OpNegBits: "~";
    });

  public function writeBinop(op: Binop)
    write(switch (op) {
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
      case OpAssignOp(op):
        writeBinop(op);
        '=';
      case OpInterval: '...';
      case OpArrow: '=>';
      case OpIn: ' in ';
    });

  function writeNewline() {
    write('\n');
    for (i in 0...indent)
      write('\t');
  }

  function writeSpace()
    write(' ');

  function writeQuotes()
    write('"');

  function writeKeyword(keyword: String)
    write(keyword);

  function writehxEnums() {
    final key = "$hxEnums";
    final global = '(typeof window!=="undefined"?window:global)';
    write('((g,k)=>g[k]||(g[k]={}))($global,"$key")');
  }

  // Utilities

  function increaseIndent()
    indent++;

  function decreaseIndent()
    indent--;
}
