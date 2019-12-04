package genes;

import haxe.macro.Type;

typedef Context = {
  expr: (expr: TypedExpr) -> String,
  value: (expr: TypedExpr) -> String,
  hasFeature: (feature: String) -> Bool,
  addFeature: (feature: String) -> Void,
  typeAccessor: (type: TypeAccessor) -> String
}
