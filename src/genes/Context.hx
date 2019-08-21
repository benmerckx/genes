package genes;

import haxe.macro.Type;

typedef Context = {
  final ?expr: (expr: TypedExpr) -> String;
  final ?value: (expr: TypedExpr) -> String;
  final ?hasFeature: (feature: String) -> Bool;
  final ?addFeature: (feature: String) -> Void;
  final ?typeAccessor: (type: ModuleType) -> String;
}
