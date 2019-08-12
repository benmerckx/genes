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
    return node(e, read(ctx -> switch (e.expr) {
      case TConst(c): constant(c);
      case TLocal(v): ident(v.name);
      case TArray(e1, e2): 
        [value(addObjectdeclParens(e1)), '[', value(e2), ']'];
      case TBinop(op, {expr: TField(x, f)}, e2) if (fieldName(f) == 'iterator'): 
        [value(x), field('iterator'), ' ', binop(op), ' ', value(e2)];
      case TBinop(op, e1, e2): [value(e1), ' ', binop(op), ' ', value(e2)];
      case TField(x, f) if (fieldName(f) == "iterator" && isDynamicIterator(ctx, e)):
				ctx.addFeature("use.$iterator");
        ["$iterator(", value(x), ")"];
/*
      case TUnop(op, flag, fe={eexpr:TField(x, f)}) if (core.Type.field_name(f) == "iterator" && is_dynamic_iterator(ctx, fe)):
				switch (flag) {
					case Prefix:
						spr(ctx, core.Ast.s_unop(op));
						gen_value(ctx, x);
						spr(ctx, ".iterator");
					case Postfix:
						gen_value(ctx, x);
						spr(ctx, ".iterator");
						spr(ctx, core.Ast.s_unop(op));
				}
			case TField(x, FClosure(Some({c:{cl_path:{a:[], b:"Array"}}}), {cf_name:"push"})):
				// see https://github.com/HaxeFoundation/haxe/issues/1997
				add_feature(ctx, "use.$arrayPush");
				add_feature(ctx, "use.$bind");
				print(ctx, "$bind(");
				gen_value(ctx, x);
				print(ctx, ",$arrayPush");
			case TField(x, FClosure(_, f)):
				add_feature(ctx, "use.$bind");
				switch (x.eexpr) {
					case TConst(_), TLocal(_):
						print(ctx, "$bind(");
						gen_value(ctx, x);
						print(ctx, ",");
						gen_value(ctx, x);
						print(ctx, '${(core.Meta.has(SelfCall, f.cf_meta)) ? "" : field(f.cf_name)})');
					case _:
						print(ctx, "($_=");
						gen_value(ctx, x);
						print(ctx, ',$$bind($$_,$$_${(core.Meta.has(SelfCall, f.cf_meta)) ? "" : field(f.cf_name)}))');
				}
*/
			case TEnumIndex(x):
				[value(x), ".$type"];
			case TEnumParameter(x, f, i):
        var fname = switch f.type {
          case TFun(args, _): args[i].name;
          case _: throw 'assert';
        }
				[value(x), field(fname)];
/*
			case TField(_, FStatic({cl_path:{a:Tl, b:""}}, f)):
				spr(ctx, f.cf_name);
			case TField(x, (FInstance(_,_,f)|FStatic(_,f)|FAnon(f))) if (core.Meta.has(SelfCall, f.cf_meta)):
				gen_value(ctx, x);
			case TField(x, f):
				function skip (e:TExpr) : TExpr {
					return switch (e.eexpr) {
						case TCast(e1, None), TMeta(_, e1):
							skip(e1);
						case TConst(TInt(_)|TFloat(_)), TObjectDecl(_):
							e.with({eexpr:TParenthesis(e)});
						case _:
							e;
					}
				}
				var x = skip(x);
				gen_value(ctx, x);
				var name = core.Type.field_name(f);
				spr(ctx, switch (f) { case FStatic(c,_): static_field(c, name); case FEnum(_), FInstance(_), FAnon(_), FDynamic(_), FClosure(_): field(name); });
			case TTypeExpr(t):
				spr(ctx, ctx.type_accessor(t));
*/
      case TParenthesis(e1): 
        ['(', expr(e1), ')'];
/*
			case TMeta({name:LoopLabel, params:[{expr:EConst(CInt(n))}]}, e):
				switch (e.eexpr) {
					case TWhile(_,_,_), TFor(_,_,_):
						print(ctx, '_hx_loop${n}: ');
						gen_expr(ctx, e);
					case TBreak:
						print(ctx, 'break _hx_loop${n}');
					case _:
						trace("Shall not be seen"); std.Sys.exit(255);
				}
*/
			case TMeta(_, e):
				expr(e);
      case TReturn(e):
        switch e {
          case null: node(e, 'return');
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
          write(ctx -> {tabs: ctx.tabs + '\t'},
            el.map(e -> blockElement(e))
          ),
          newline,
          '}'
        ];
      case TFunction(f): 
        write(ctx -> {inValue: false, inLoop: false}, [
          'function (', f.args.map(a -> ident(a.v.name)), ') ',
          expr(f.expr)
        ]);
      case TCall(e, el): 
        call(e, el, false);
			case TArrayDecl(el):
				['[', join(el.map(value), ', '), ']'];
			case TThrow(e):
        ['throw ', value(e)];
      case TVar(v, eo): 
        [
          'var ', ident(v.name),
          switch (eo) {
            case null: '';
            case e: [' = ', value(e)];
          }
        ];
/*
case TNew({cl_path:{a:[], b:"Array"}}, _, []):
				print(ctx, "[]");
			case TNew(c, _, el):
				switch (c.cl_constructor) {
					case Some(cf) if (core.Meta.has(SelfCall, cf.cf_meta)):
					case _:
						print(ctx, "new ");
				}
				print(ctx, '${ctx.type_accessor(TClassDecl(c))}(');
				concat(ctx, ",", gen_value.bind(ctx), el);
				spr(ctx, ")");
			case TIf(cond, e, eelse):
				spr(ctx, "if");
				gen_value(ctx, cond);
				spr(ctx, " ");
				gen_expr(ctx, core.Type.mk_block(e));
				switch (eelse) {
					case None:
					case Some(e2):
						switch (e.eexpr) {
							case TObjectDecl(_): ctx.separator = false;
							case _:
						}
						semicolon(ctx);
						spr(ctx, " else ");
						gen_expr(ctx, switch (e2.eexpr) { case TIf(_,_,_): e2; case _: core.Type.mk_block(e2);});
				}
			case TUnop(op, Prefix, e):
				spr(ctx, core.Ast.s_unop(op));
				gen_value(ctx, e);
			case TUnop(op, Postfix, e):
				gen_value(ctx, e);
				spr(ctx, core.Ast.s_unop(op));
			case TWhile(cond, e, NormalWhile):
				var old_in_loop = ctx.in_loop;
				ctx.in_loop = true;
				spr(ctx, "while");
				gen_value(ctx, cond);
				spr(ctx, " ");
				gen_expr(ctx, e);
				ctx.in_loop = old_in_loop;
			case TWhile(cond, e, DoWhile):
				var old_in_loop = ctx.in_loop;
				ctx.in_loop = true;
				spr(ctx, "do ");
				gen_expr(ctx, e);
				semicolon(ctx);
				spr(ctx, "while");
				gen_value(ctx, cond);
				ctx.in_loop = old_in_loop;
			case TObjectDecl(fields):
				spr(ctx, "{");
				concat(ctx, ", ", function (field:TObjectField) {
					var f = field.name; var qs = field.quotes; var e = field.expr;
					switch (qs) {
						case DoubleQuotes:
							print(ctx, '"${core.Ast.s_escape(f)}" : ');
						case NoQuotes:
							print(ctx, '${anon_field(f)} ; ');
					}
				}, fields);
				spr(ctx, "}");
				ctx.separator = true;
			case TFor(v, it, e):
				check_var_declaration(v);
				var old_in_loop = ctx.in_loop;
				ctx.in_loop = true;
				var it = ident(switch (it.eexpr) {
					case TLocal(v): v.v_name;
					case _:
						var id = ctx.id_counter;
						ctx.id_counter++;
						var name = "$it" + id;
						print(ctx, 'var ${name} = ');
						gen_value(ctx, it);
						newline(ctx);
						name;
				});
				print(ctx, 'while ( ${it}.hasNext() ) {');
				var bend = open_block(ctx);
				newline(ctx);
				print(ctx, 'var ${ident(v.v_name)} = ${it}.next()');
				gen_block_element(ctx, e);
				bend();
				newline(ctx);
				spr(ctx, "}");
				ctx.in_loop = old_in_loop;
			case TTry(etry, [{v:v, e:ecatch}]):
				spr(ctx, "try ");
				gen_expr(ctx, etry);
				check_var_declaration(v);
				print(ctx, ' catch ( ${v.v_name} ) ');
				gen_expr(ctx, ecatch);
			case TTry(_):
				context.Common.abort("Unhandled try/catch, please report", e.epos);
			case TSwitch(e, cases, def):
				spr(ctx, "switch");
				gen_value(ctx, e);
				spr(ctx, " {");
				newline(ctx);
				List.iter(function (c) {
					var el = c.values; var e2 = c.e;
					List.iter (function (e) {
						switch (e.eexpr) {
							case TConst(c) if (c == TNull):
								spr(ctx, "case null: case undefined:");
							case _:
								spr(ctx, "case ");
								gen_value(ctx, e);
								spr(ctx, ":");
						}
					}, el);
					var bend = open_block(ctx);
					gen_block_element(ctx, e2);
					if (needs_switch_break(e2)) {
						newline(ctx);
						print(ctx, "break");
					}
					bend();
					newline(ctx);
				}, cases);
				switch(def) {
					case None:
					case Some(e):
						spr(ctx, "default:");
						var bend = open_block(ctx);
						gen_block_element(ctx, e);
						bend();
						newline(ctx);
				}
				spr(ctx, "}");
			case TCast(e, None):
				gen_expr(ctx, e);
			case TCast(e1, Some(t)):
				print(ctx, '${ctx.type_accessor(TClassDecl(core.Type.null_class.with({cl_path:{a:["js"], b:"Boot"}})))}.__cast(');
				gen_expr(ctx, e1);
				spr(ctx, " , ");
				spr(ctx, ctx.type_accessor(t));
				spr(ctx, ")");
*/
      case TIdent(s): s;
      default:
        [];
    }));

  static function ident(name: String): SourceNode
    return if (keywords.indexOf(name) > -1) "$" + name else name;

  static function field(name: String): String // Todo: check valid js ident
		return if (keywords.indexOf(name) > -1) '["${name}"]' else '.${name}';

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

  static function addObjectdeclParens(e: TypedExpr): TypedExpr {
    function loop(e:TypedExpr): TypedExpr
      return switch (e.expr) {
        case TCast(e1, null), TMeta(_, e1): loop(e1);
        case TObjectDecl(_): {expr: TParenthesis(e), t: e.t, pos: e.pos}
        case _: e;
      }
    return loop(e);
  }

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
    return node(e, switch e.expr {
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

  static function isDynamicIterator(ctx: Context, e: TypedExpr): Bool
		return switch (e.expr) {
			case TField(x, f) if (fieldName(f) == "iterator"):
				ctx.hasFeature('HxOverrides.iter') && 
          switch haxe.macro.Context.followWithAbstracts(e.t) {
            case //TInst({cl_path: {a:Tl, b: "Array"}}, _), // Todo: check array inst
              TInst(_.get() => {kind: KTypeParameter(_)}, _) |
              TAnonymous(_), TDynamic(_), TMono(_):
              true;
            case _:
              false;
          }
			case _:
				false;
		}

  static function fieldName(f: FieldAccess): String
    return switch f {
      case FAnon(f), FInstance(_,_, f), FStatic(_, f), FClosure(_, f):
        f.get().name;
      case FEnum(_, f) : f.name;
      case FDynamic(n): n;
    }

  static function stringEscape(?hex = true, s: String): String {
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
