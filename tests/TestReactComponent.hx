package tests;

// See benmerckx/genes#6

@:jsRequire("react")
private extern class React {
  public static function createElement(type: Dynamic, ?attrs: Dynamic,
    children: haxe.extern.Rest<Dynamic>): Dynamic;
}

@:jsRequire("react-dom/server")
private extern class ReactDOMServer {
  public static function renderToString(element: Dynamic): String;
}

// @:native without a require should work in this case since React was imported

@:native('React.Fragment')
private extern class Fragment {}

@:jsRequire("react", "Component")
@:native('React.Component')
private extern class NativeComponent<State, Props> {
  var props(default, null): Props;
  var state(default, null): State;
  function setState(state: State): Void;
  function new(): Void;
  @:native('forceUpdate') function forceRerender(): Void;
}

class ViewBase extends NativeComponent<{}, {}> {
  var test = 0;

  public function new() {
    test++;
    super();
    test++;
  }
}

class MyComponent extends ViewBase {
  @:keep public function render() {
    return test;
  }
}

@:asserts
class TestReactComponent {
  public function new() {}

  public function testCreateComponent() {
    var vdom = React.createElement(MyComponent);
    asserts.assert(ReactDOMServer.renderToString(vdom) == '2');
    asserts.assert(Fragment != null);
    return asserts.done();
  }
}
