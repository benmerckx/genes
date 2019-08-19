package genes;

import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Expr.Position;
import genes.generator.es.ExprGenerator.*;

using StringTools;
using haxe.macro.TypedExprTools;

enum FieldKind {
  Constructor;
  Method;
  Property;
}

typedef Field = {
  final kind: FieldKind;
  final name: String;
  final type: Type;
  final expr: TypedExpr;
  final pos: Position;
  final isStatic: Bool;
}

enum Member {
  MClass(type: ClassType, fields: Array<Field>);
  MEnum(type: EnumType);
  MMain(expr: TypedExpr);
}

enum DependencyType {
  DName;
  DDefault;
}

typedef Dependency = {
  type: DependencyType,
  name: String,
  ?alias: String
}

private typedef ModuleName = String;

class Module {
  public final path: String;
  public final file: Null<String>;
  public final members: Array<Member>;
  public final dependencies: Map<ModuleName, Array<Dependency>>;

  public function new(path, file, types: Array<Type>, ?main: TypedExpr) {
    this.path = path;
    this.file = file;
    members = [
      for (type in types)
        switch type {
          case TEnum(_.get() => et, _):
            MEnum(et);
          case TInst(_.get() => cl, _):
            MClass(cl, fieldsOf(cl));
          default:
            throw 'assert';
        }
    ];
    if (main != null)
      members.push(MMain(main));
    dependencies = createDependencies();
  }

  function toPath(module: String) {
    final parts = module.split('.');
    final dirs = path.split('/');
    return switch dirs.length {
      case 1: './' + parts.join('/');
      case v:
        [for (i in 0...v - 1) '..'].concat(parts).join('/');
    }
  }

  static function getModuleType(module: String): ModuleType
    return switch haxe.macro.Context.getType(module) {
      case TEnum(r, _): TEnumDecl(r);
      case TInst(r, _): TClassDecl(r);
      case TType(r, _): TTypeDecl(r);
      case TAbstract(r, _): TAbstract(r);
      case _: throw 'assert';
    }

  function createDependencies() {
    final dependencies = new Map<ModuleName, Array<Dependency>>();
    final aliasCount = new Map<String, Int>();
    function push(module: String, dependency: Dependency) {
      // Check for name clashes
      for (member in members)
        switch member {
          case MClass({name: name}, _) | MEnum({name: name}):
            if (name == dependency.name) {
              dependency.alias = name + '__' +
                (aliasCount[name] = switch aliasCount[name] {
                case null: 1;
                case v: v + 1;
              });
              break;
            }
          default:
        }
      if (dependencies.exists(module)) {
        final imports = dependencies.get(module);
        for (i in imports)
          if (i.name == dependency.name && i.alias == dependency.alias)
            return;
        imports.push(dependency);
      } else {
        dependencies.set(module, [dependency]);
      }
    }
    function add(type: ModuleType) {
      switch type {
        case TClassDecl(_.get() => {isInterface: true}):
        case TClassDecl((_.get() : BaseType) => base) | TEnumDecl((_.get() : BaseType) => base):
          // check meta
          var module = toPath(base.module) +
            '.mjs'; // Todo: don't hardcode extension here
          var dependency: Dependency = {type: DName, name: base.name}
          if (base.isExtern) {
            final name = switch base.meta.extract(':native') {
              case [{params: [{expr: EConst(CString(name))}]}]:
                name;
              default: base.name;
            }
            switch base.meta.extract(':jsRequire') {
              case [{params: [{expr: EConst(CString(m))}]}]:
                module = m;
                dependency = {type: DDefault, name: name}
              default:
                return;
            }
          } else if (base.module.replace('.', '/') == path) {
            return;
          }
          push(module, dependency);
        default:
      }
    }
    function addFromExpr(e: TypedExpr)
      switch e {
        case null:
        case {expr: TTypeExpr(t)}:
          add(t);
        case {expr: TNew(c, _, el)}:
          add(TClassDecl(c));
          for (e in el)
            addFromExpr(e);
        case {expr: TField(x, f)}
          if (fieldName(f) == "iterator"): // Todo: conditions here could be refined
          add(getModuleType('HxOverrides'));
          addFromExpr(x);
        case e:
          e.iter(addFromExpr);
      }
    for (member in members) {
      switch member {
        case MClass(cl, fields):
          switch cl.interfaces {
            case null | []:
            case v:
              for (i in v)
                add(TClassDecl(i.t));
          }
          switch cl.superClass {
            case null:
            case {t: t}: add(TClassDecl(t));
          }
          for (field in fields)
            addFromExpr(field.expr);
          addFromExpr(cl.init);
        case MMain(expr):
          addFromExpr(expr);
        default:
      }
    }
    return dependencies;
  }

  public function typeAccessor(type: ModuleType)
    switch type {
      case TAbstract(_.get() => cl = {meta: meta, name: name}):
        return switch meta.has(':coreType') {
          case true: '"$$hxCoreType__$name"';
          case false: throw 'assert';
        }
      case TClassDecl(_.get() => {
        module: module,
        name: name
      }) | TEnumDecl(_.get() => {module: module, name: name}):
        // check alias in this module
        final path = toPath(module) + '.mjs';
        final imports = dependencies.get(path);
        if (imports != null)
          for (i in imports)
            if (i.name == name)
              return if (i.alias != null) i.alias else i.name;
        return name;
      case TTypeDecl(_.get() => {name: name}):
        return name; // Todo: does this even happen?
    }

  static function fieldsOf(cl: ClassType) {
    final fields = [];
    switch cl.constructor {
      case null:
      case ctor:
        final e = ctor.get().expr();
        fields.push({
          kind: Constructor,
          type: e.t,
          expr: e,
          pos: e.pos,
          name: 'constructor',
          isStatic: false
        });
    }
    for (field in cl.fields.get()) {
      fields.push({
        kind: switch field.kind {
          case FVar(_, _): Property;
          case FMethod(_): Method;
        },
        name: field.name,
        type: field.type,
        expr: field.expr(),
        pos: field.pos,
        isStatic: false
      });
    }
    for (field in cl.statics.get())
      fields.push({
        kind: switch field.kind {
          case FVar(_, _): Property;
          case FMethod(_): Method;
        },
        name: field.name,
        type: field.type,
        expr: field.expr(),
        pos: field.pos,
        isStatic: true
      });
    return fields;
  }
}
