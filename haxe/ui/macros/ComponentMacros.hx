package haxe.ui.macros;

import haxe.macro.ExprTools;
import haxe.ui.core.ComponentClassMap;
import haxe.ui.core.LayoutClassMap;
import haxe.ui.parsers.ui.ComponentInfo;
import haxe.ui.parsers.ui.ComponentParser;
import haxe.ui.parsers.ui.LayoutInfo;
import haxe.ui.parsers.ui.resolvers.FileResourceResolver;
import haxe.ui.scripting.ConditionEvaluator;
import haxe.ui.core.ComponentFieldMap;
import haxe.ui.core.ComponentFieldMap;
import haxe.ui.util.StringUtil;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;
#end

class ComponentMacros {
    macro public static function build(resourcePath:String, params:Expr = null, alias:String = null):Array<Field> {
        var pos = haxe.macro.Context.currentPos();
        var fields = haxe.macro.Context.getBuildFields();

        var ctor = MacroHelpers.getConstructor(fields);
        if (MacroHelpers.hasSuperClass(Context.getLocalType(), "haxe.ui.core.Component") == false) {
            Context.error("Must have a superclass of haxe.ui.core.Component", Context.currentPos());
        }

        if (ctor == null) Context.error("A class building component must have a constructor", Context.currentPos());

        var originalRes = resourcePath;
        resourcePath = MacroHelpers.resolveFile(resourcePath);
        if (resourcePath == null || sys.FileSystem.exists(resourcePath) == false) {
            Context.error('UI markup file "${originalRes}" not found', Context.currentPos());
        }

        ModuleMacros.populateClassMap();

        var namedComponents:Map<String, String> = new Map<String, String>();
        var code:Expr = buildComponentFromFile([], resourcePath, namedComponents, MacroHelpers.exprToMap(params));
        var e:Expr = macro addComponent($code);
        //code += "this.addClass('custom-component');";
        //trace(code);

        var n:Int = 1;
        ctor.expr = switch(ctor.expr.expr) {
            case EBlock(el): macro $b{MacroHelpers.insertExpr(el, n, e)};
            case _: macro $b { MacroHelpers.insertExpr([ctor.expr], n, e) }
        }

        n++;
        for (id in namedComponents.keys()) {
            var safeId:String = StringUtil.capitalizeHyphens(id);
            var cls:String = namedComponents.get(id);
            var classArray:Array<String> = cls.split(".");
            var className = classArray.pop();
            var ttype = TPath( { pack : classArray, name : className, params : [], sub : null } );
            fields.push( { name : safeId, doc : null, meta : [], access : [APublic], kind : FVar(ttype, null), pos : pos } );

            var e:Expr = Context.parseInlineString('this.${safeId} = findComponent("${id}", ${cls}, true)', Context.currentPos());
            ctor.expr = switch(ctor.expr.expr) {
                case EBlock(el): macro $b{MacroHelpers.insertExpr(el, n, e)};
                case _: macro $b { MacroHelpers.insertExpr([ctor.expr], n, e) }
            }
        }

        var resolvedClass:String = "" + Context.getLocalClass();
        if (alias == null) {
            alias = resolvedClass.substr(resolvedClass.lastIndexOf(".") + 1, resolvedClass.length);
        }
        alias = alias.toLowerCase();

        var e:Expr = Context.parseInlineString('this.addClass("custom-component")', Context.currentPos());
        ctor.expr = switch(ctor.expr.expr) {
            case EBlock(el): macro $b{MacroHelpers.insertExpr(el, n, e)};
            case _: macro $b { MacroHelpers.insertExpr([ctor.expr], n, e) }
        }

        var e:Expr = Context.parseInlineString('this.addClass("${alias}-container")', Context.currentPos());
        ctor.expr = switch(ctor.expr.expr) {
            case EBlock(el): macro $b{MacroHelpers.insertExpr(el, n, e)};
            case _: macro $b { MacroHelpers.insertExpr([ctor.expr], n, e) }
        }

        ComponentClassMap.register(alias, resolvedClass);

        return fields;
    }

    macro public static function buildComponent(filePath:String, params:Expr = null):Expr {
        return buildComponentFromFile([], filePath, null, MacroHelpers.exprToMap(params));
    }

    #if macro
    public static function buildComponentFromFile(code:Array<Expr>, filePath:String, namedComponents:Map<String, String> = null, params:Map<String, Dynamic> = null):Expr {
        ModuleMacros.populateClassMap();

        var f = MacroHelpers.resolveFile(filePath);
        if (f == null) {
            throw "Could not resolve: " + filePath;
        }

        var fileContent:String = StringUtil.replaceVars(File.getContent(f), params);
        var c:ComponentInfo = ComponentParser.get(MacroHelpers.extension(f)).parse(fileContent, new FileResourceResolver(f, params));
        return buildComponentSource(code, c, namedComponents, params);
    }

    public static function buildComponentFromString(code:Array<Expr>, source:String, namedComponents:Map<String, String> = null, params:Map<String, Dynamic> = null):Expr {
        ModuleMacros.populateClassMap();

        source = StringUtil.replaceVars(source, params);
        var c:ComponentInfo = ComponentParser.get("xml").parse(source);
        return buildComponentSource(code, c, namedComponents, params);
    }

    private static var bindingInfo:Array<Dynamic> = [];
    public static function buildComponentSource(code:Array<Expr>, c:ComponentInfo, namedComponents:Map<String, String> = null, params:Map<String, Dynamic> = null):Expr {
        //trace(c);

        bindingInfo = [];

        for (styleString in c.styles) {
            code.push(macro haxe.ui.Toolkit.styleSheet.parse($v{styleString}));
        }

        _componentId = 0;
        buildComponentCode(code, c, -1, namedComponents, Context.currentPos());
        assignBindings(code, c.bindings);

        var fullScript = "";
        for (scriptString in c.scriptlets) {
            fullScript += scriptString;
        }

        for (b in bindingInfo) {
            code.push(macro haxe.ui.binding.BindingManager.instance.add($i{b.componentVarName}, $v{b.field}, $v{b.value}));
        }

        code.push(macro c0.script = $v{fullScript});
        code.push(macro c0.bindingRoot = true);
        code.push(macro c0);

//        trace(ExprTools.toString(macro @:pos(Context.currentPos()) $b{code}));

        return macro @:pos(Context.currentPos()) $b{code};
    }

    private static var _componentId:Int = 0;
    private static function buildComponentCode(code:Array<Expr>, c:ComponentInfo, parentId:Int, namedComponents:Map<String, String>, pos:Position = null) {
        if (c.condition != null && new ConditionEvaluator().evaluate(c.condition) == false) {
            return;
        }

        var className:String = ComponentClassMap.get(c.type.toLowerCase());
        if (className == null) {
            if (pos == null) {
                pos = Context.currentPos();
            }
            Context.warning("no class found for component: " + c.type, pos);
            return;
        }

        var numberEReg:EReg = ~/^-?\d+(\.(\d+))?$/;
        var localeEReg = ~/^_\( *([\w'", \.]+) *\)$/;
        var localeStringParamEReg = ~/['"](.+)['"]/;
        var type = Context.getModule(className)[0];
        if (MacroHelpers.hasDirectInterface(type, "haxe.ui.core.IDirectionalComponent")) {
            var direction = c.direction;
            if (direction == null) {
                direction = "horizontal"; // default to horizontal
            }
            var directionalClassName = ComponentClassMap.get(direction + c.type.toLowerCase());
            if (directionalClassName == null) {
                trace("WARNING: no direction class found for component: " + c.type + " (" + (direction + c.type.toLowerCase()) + ")");
                return;
            }

            className = directionalClassName;
            type = Context.getModule(className)[0];
        }

        var componentVarName = 'c${_componentId}';
        var orgId = _componentId;
        _componentId++;
        var typePath = {
            var split = className.split(".");
            { name: split.pop(), pack: split }
        };

        inline function add(e:Expr) {
            code.push(e);
        }
        inline function assign(field:String, value:Dynamic) {
            if (Std.string(value).indexOf("${") != -1) {
                bindingInfo.push({
                    componentVarName: componentVarName,
                    field: field,
                    value: value
                });
            }
            add(macro $i{componentVarName}.$field = $v{value});
        }
        function assignText(field:String, value:String) {
            if (localeEReg.match(value)) {
                var localeMatched = localeEReg.matched(1);
                var localeArr = localeMatched.split(",");
                var localeID = localeArr[0];
                if (!localeStringParamEReg.match(localeID)) {
                    throw 'First parameter $localeID in locale function isn\'t a string.';
                }

                localeID = localeStringParamEReg.matched(1);
                var localeParams = localeArr.slice(1, localeArr.length);

                var onLocaleChangeCode:Array<Expr> = [];
                var rootComponent:ComponentInfo = null;
                if (localeParams != null && localeParams.length > 0) {
                    onLocaleChangeCode.push(macro var params:Array<Any> = []);
                    for (i in 0...localeParams.length) {
                        var param = StringTools.trim(localeParams[i]);
                        localeParams[i] = param;

                        if (localeStringParamEReg.match(param)) {
                            onLocaleChangeCode.push(macro params.push($v{localeStringParamEReg.matched(1)}));
                        } else if (param.indexOf(".") != -1) {
                            var sourceArr:Array<String> = param.split(".");
                            var sourceId:String = sourceArr[0];
                            var sourceProp:String = sourceArr[1];
                            onLocaleChangeCode.push(macro var source = c0.findComponent($v{sourceId}, null, true));
                            onLocaleChangeCode.push(macro params.push(haxe.ui.util.Variant.toDynamic(Reflect.getProperty(source, $v{sourceProp}))));

                            var binding:ComponentBindingInfo = new ComponentBindingInfo();
                            binding.source = sourceId;
                            if (c.id == null) {
                                c.id = @:privateAccess ComponentParser.nextId();
                                assign("id", c.id);
                            }
                            binding.target = c.id;
                            if (rootComponent == null) {
                                rootComponent = c.findRootComponent();
                            }
                            binding.transform = "${" + '${binding.target}.${field} = LocaleManager.instance.get("${localeID}", ${localeParams.toString()})' + "}";
                            rootComponent.bindings.push(binding);
                        } else {
                            onLocaleChangeCode.push(macro params.push(Std.string($v{param})));
                        }
                    }

                    onLocaleChangeCode.push(macro $i{componentVarName}.$field = haxe.ui.locale.LocaleManager.instance.get($v{localeID}, params));
                } else {
                    onLocaleChangeCode.push(macro $i{componentVarName}.$field = haxe.ui.locale.LocaleManager.instance.get($v{localeID}));
                }

                add(macro {
                    var _onLocaleChange = function(_) {
                        $b{onLocaleChangeCode}
                    };
                    $i{componentVarName}.registerEvent(haxe.ui.core.UIEvent.READY, function(_) {
                        haxe.ui.locale.LocaleManager.instance.registerEvent(haxe.ui.core.UIEvent.CHANGE, _onLocaleChange);
                        _onLocaleChange(null);
                    });
                    $i{componentVarName}.registerEvent(haxe.ui.core.UIEvent.DESTROY, function(_) {
                        haxe.ui.locale.LocaleManager.instance.unregisterEvent(haxe.ui.core.UIEvent.CHANGE, _onLocaleChange);
                    });
                });

            } else {
                assign(field, value);
            }
        }
        add(macro var $componentVarName = new $typePath());

        var childParentId = _componentId - 1;
        for (child in c.children) {
            buildComponentCode(code, child, childParentId, namedComponents, pos);

        }

        if (c.id != null)                       assign("id", c.id);
        if (c.left != null)                     assign("left", c.left);
        if (c.top != null)                      assign("top", c.top);
        if (c.width != null)                    assign("width", c.width);
        if (c.height != null)                   assign("height", c.height);
        if (c.percentWidth != null)             assign("percentWidth", c.percentWidth);
        if (c.percentHeight != null)            assign("percentHeight", c.percentHeight);
        if (c.contentWidth != null)             assign("contentWidth", c.contentWidth);
        if (c.contentHeight != null)            assign("contentHeight", c.contentHeight);
        if (c.percentContentWidth != null)      assign("percentContentWidth", c.percentContentWidth);
        if (c.percentContentHeight != null)     assign("percentContentHeight", c.percentContentHeight);
        if (c.text != null)                     assignText("text", c.text);
        if (c.styleNames != null)               assign("styleNames", c.styleNames);
        if (c.style != null)                    assign("styleString", c.styleString);
        if (c.layout != null) {
            buildLayoutCode(code, c.layout, orgId, namedComponents, pos);
        }

        for (propName in c.properties.keys()) {
            var propValue = c.properties.get(propName);
            propName = ComponentFieldMap.mapField(propName);
            var propExpr = if (propValue == "true" || propValue == "yes" || propValue == "false" || propValue == "no") {
                macro $v{propValue == "true" || propValue == "yes"};
            } else {
                if(numberEReg.match(propValue)) {
                    if(numberEReg.matched(2) != null) {
                        macro $v{Std.parseFloat(propValue)};
                    } else {
                        macro $v{Std.parseInt(propValue)};
                    }
                } else if (localeEReg.match(propValue)) {
                    assignText(propName, propValue);
                } else {
                    macro $v{propValue};
                }
            }

            if (StringTools.startsWith(propName, "on")) {
                add(macro $i{componentVarName}.addScriptEvent($v{propName}, $propExpr));
            } else if (Std.string(propValue).indexOf("${") != -1) {
                bindingInfo.push({
                    componentVarName: componentVarName,
                    field: propName,
                    value: propValue
                });
                // TODO: does this make sense? Basically, if you try to apply a bound variable to something that isnt
                // a string, then we cant assign it as normal, ie:
                //     c5.selectedIndex = ${something}
                // but, if we skip it, then you can use non-existing xml attributes in the xml (eg: fakeComponentProperty)
                // and they will go unchecked and you wont get an error. This is a way around that, so it essentially generates
                // the following expr:
                //     c5.fakeComponentProperty = c5.fakeComponentProperty
                // which will result in a compile time error
                add(macro $i{componentVarName}.$propName = $i{componentVarName}.$propName);
            } else {
                add(macro $i{componentVarName}.$propName = $propExpr);
            }
        }

        if (MacroHelpers.hasInterface(type, "haxe.ui.core.IDataComponent") == true && c.data != null) {
            add(macro ($i{componentVarName} : haxe.ui.core.IDataComponent).dataSource = new haxe.ui.data.DataSourceFactory<Dynamic>().fromString($v{c.dataString}, haxe.ui.data.ArrayDataSource));
        }

        if (c.id != null && namedComponents != null) {
            namedComponents.set(c.id, className);
        }

        if (parentId != -1) {
            add(macro $i{"c" + (parentId)}.addComponent($i{componentVarName}));
        }
    }

    private static function buildLayoutCode(code:Array<Expr>, l:LayoutInfo, id:Int, namedComponents:Map<String, String>, pos:Position = null) {
        var className:String = LayoutClassMap.get(l.type.toLowerCase());
        if (className == null) {
            if (pos == null) {
                pos = Context.currentPos();
            }
            Context.warning("no class found for layout: " + l.type, pos);
            return;
        }

        var numberEReg:EReg = ~/^-?\d+(\.(\d+))?$/;
        var type = Context.getModule(className)[0];

        var layoutVarName = 'l${id}';
        var typePath = {
            var split = className.split(".");
            { name: split.pop(), pack: split }
        };
        inline function add(e:Expr) {
            code.push(e);
        }
        inline function assign(field:String, value:Dynamic) {
            add(macro $i{layoutVarName}.$field = $v{value});
        }
        add(macro var $layoutVarName = new $typePath());

        for (propName in l.properties.keys()) {
            var propValue = l.properties.get(propName);
            var propExpr = if (propValue == "true" || propValue == "yes" || propValue == "false" || propValue == "no") {
                macro $v{propValue == "true" || propValue == "yes"};
            } else {
                if(numberEReg.match(propValue)) {
                    if(numberEReg.matched(2) != null) {
                        macro $v{Std.parseFloat(propValue)};
                    } else {
                        macro $v{Std.parseInt(propValue)};
                    }
                } else {
                    macro $v{propValue};
                }
            }

            add(macro $i{layoutVarName}.$propName = $propExpr);
        }

        if (id != 0) {
            add(macro $i{"c" + (id)}.layout = $i{"l" + id});
        }
    }

    private static function assignBindings(code:Array<Expr>, bindings:Array<ComponentBindingInfo>) {
        for (b in bindings) {
            var source:Array<String> = b.source.split(".");
            var target:Array<String> = b.target.split(".");
            var transform:String = b.transform;
            var targetProp = target[1];
            var sourceProp = source[1];
            code.push(macro var source = c0.findComponent($v{source[0]}, null, true));
            code.push(macro var target = c0.findComponent($v{target[0]}, null, true));
            code.push(macro
                if (source != null && target != null)
                    source.addBinding(target, $v{transform}, $v{targetProp}, $v{sourceProp});
                else
                    c0.addDeferredBinding($v{target[0]}, $v{source[0]}, $v{transform}, $v{targetProp}, $v{sourceProp})
            );
        }
    }
    #end
}