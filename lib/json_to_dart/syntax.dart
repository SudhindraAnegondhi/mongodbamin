import 'package:json_ast/json_ast.dart' show Node;
import './helpers.dart';

const String emptyListWarn = "list is empty";
const String ambiguousListWarn = "list is ambiguous";
const String ambiguousTypeWarn = "type is ambiguous";

class Warning {
  final String warning;
  final String path;

  Warning(this.warning, this.path);
}

class Customization {
  String primaryKey;
  Map<String, dynamic> foreignKeys;
  List<dynamic> noUpdate;
  List<Map<String, dynamic>> index;
  Customization({this.foreignKeys, this.noUpdate, this.primaryKey, this.index});
}

Warning newEmptyListWarn(String path) {
  return new Warning(emptyListWarn, path);
}

Warning newAmbiguousListWarn(String path) {
  return new Warning(ambiguousListWarn, path);
}

Warning newAmbiguousType(String path) {
  return new Warning(ambiguousTypeWarn, path);
}

class WithWarning<T> {
  final T result;
  final List<Warning> warnings;

  WithWarning(this.result, this.warnings);
}

class TypeDefinition {
  String name;
  String subtype;
  bool isAmbiguous = false;
  bool _isPrimitive = false;

  factory TypeDefinition.fromDynamic(dynamic obj, Node astNode) {
    bool isAmbiguous = false;
    final type = getTypeName(obj);
    if (type == 'List') {
      List<dynamic> list = obj;
      String elemType;
      if (list.length > 0) {
        elemType = getTypeName(list[0]);
        for (dynamic listVal in list) {
          if (elemType != getTypeName(listVal)) {
            isAmbiguous = true;
            break;
          }
        }
      } else {
        // when array is empty insert Null just to warn the user
        elemType = "Null";
      }
      return new TypeDefinition(type,
          astNode: astNode, subtype: elemType, isAmbiguous: isAmbiguous);
    }
    return new TypeDefinition(type, astNode: astNode, isAmbiguous: isAmbiguous);
  }

  TypeDefinition(this.name, {this.subtype, this.isAmbiguous, Node astNode}) {
    if (subtype == null) {
      _isPrimitive = isPrimitiveType(this.name);
      if (this.name == 'int' && isASTLiteralDouble(astNode)) {
        this.name = 'double';
      }
    } else {
      _isPrimitive = isPrimitiveType('$name<$subtype>');
    }
    if (isAmbiguous == null) {
      isAmbiguous = false;
    }
  }

  bool operator ==(other) {
    if (other is TypeDefinition) {
      TypeDefinition otherTypeDef = other;
      return this.name == otherTypeDef.name &&
          this.subtype == otherTypeDef.subtype &&
          this.isAmbiguous == otherTypeDef.isAmbiguous &&
          this._isPrimitive == otherTypeDef._isPrimitive;
    }
    return false;
  }

  bool get isPrimitive => _isPrimitive;

  bool get isPrimitiveList => _isPrimitive && name == 'List';

  String _buildParseClass(String expression) {
    final properType = subtype != null ? subtype : name;
    return 'new $properType.fromMap($expression)';
  }

  String _buildtoMapClass(String expression) {
    return '$expression.toMap()';
  }

  String mapParseExpression(String key, bool privateField) {
    final mapKey = "map['$key']";
    final fieldKey =
        fixFieldName(key, typeDef: this, privateField: privateField);
    if (isPrimitive) {
      if (name == "List") {
        return "$fieldKey = map['$key'].cast<$subtype>();";
      }
      return "$fieldKey = map['$key'];";
    } else if (name == "List" && subtype == "DateTime") {
      return "$fieldKey = map['$key'].map((v) => DateTime.tryParse(v));";
    } else if (name == "DateTime") {
      return "$fieldKey = DateTime.tryParse(map['$key']);";
    } else if (name == 'List') {
      // list of class
      return "if (map['$key'] != null) {\n\t\t\t$fieldKey = new List<$subtype>();\n\t\t\tmap['$key'].forEach((v) { $fieldKey.add(new $subtype.fromMap(v)); });\n\t\t}";
    } else {
      // class
      return "$fieldKey = map['$key'] != null ? ${_buildParseClass(mapKey)} : null;";
    }
  }

  String toMapExpression(String key, bool privateField) {
    final fieldKey =
        fixFieldName(key, typeDef: this, privateField: privateField);
    final thisKey = 'this.$fieldKey';
    if (isPrimitive) {
      return "data['$key'] = $thisKey;";
    } else if (name == 'DateTime') {
      return "data['$key'] = '$thisKey.toIso8601String()';";
    } else if (name == 'List') {
      // class list
      return """if ($thisKey != null) {
      data['$key'] = $thisKey.map((v) => ${_buildtoMapClass('v')}).toList();
    }""";
    } else {
      // class
      return """if ($thisKey != null) {
      data['$key'] = ${_buildtoMapClass(thisKey)};
    }""";
    }
  }
}

class Dependency {
  String name;
  final TypeDefinition typeDef;

  Dependency(this.name, this.typeDef);

  String get className => camelCase(name);
}

class ClassDefinition {
  final String _name;
  final bool _privateFields;
  final Map<String, TypeDefinition> fields = new Map<String, TypeDefinition>();
  final Customization _customization;

  String get name => _name;
  bool get privateFields => _privateFields;

  List<Dependency> get dependencies {
    final dependenciesList = new List<Dependency>();
    final keys = fields.keys;
    keys.forEach((k) {
      final f = fields[k];
      if (!f.isPrimitive) {
        dependenciesList.add(new Dependency(k, f));
      }
    });
    return dependenciesList;
  }

  ClassDefinition(this._name,
      [this._privateFields = false, this._customization]);

  bool operator ==(other) {
    if (other is ClassDefinition) {
      ClassDefinition otherClassDef = other;
      return this.isSubsetOf(otherClassDef) && otherClassDef.isSubsetOf(this);
    }
    return false;
  }

  bool isSubsetOf(ClassDefinition other) {
    final List<String> keys = this.fields.keys.toList();
    final int len = keys.length;
    for (int i = 0; i < len; i++) {
      TypeDefinition otherTypeDef = other.fields[keys[i]];
      if (otherTypeDef != null) {
        TypeDefinition typeDef = this.fields[keys[i]];
        if (typeDef != otherTypeDef) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  hasField(TypeDefinition otherField) {
    return fields.keys
            .firstWhere((k) => fields[k] == otherField, orElse: () => null) !=
        null;
  }

  addField(String name, TypeDefinition typeDef) {
    fields[name] = typeDef;
  }

  void _addTypeDef(TypeDefinition typeDef, StringBuffer sb) {
    sb.write('${typeDef.name}');
    if (typeDef.subtype != null) {
      sb.write('<${typeDef.subtype}>');
    }
  }

  String get _fieldList {
    return fields.keys.map((key) {
      final f = fields[key];
      final fieldName =
          fixFieldName(key, typeDef: f, privateField: privateFields);
      final sb = new StringBuffer();
      sb.write('\t');
      _addTypeDef(f, sb);
      sb.write(' $fieldName;');
      return sb.toString();
    }).join('\n');
  }

  String get _gettersSetters {
    return fields.keys.map((key) {
      final f = fields[key];
      final publicFieldName =
          fixFieldName(key, typeDef: f, privateField: false);
      final privateFieldName =
          fixFieldName(key, typeDef: f, privateField: true);
      final sb = new StringBuffer();
      sb.write('\t');
      _addTypeDef(f, sb);
      sb.write(
          ' get $publicFieldName => $privateFieldName;\n\tset $publicFieldName(');
      _addTypeDef(f, sb);
      sb.write(' $publicFieldName) => $privateFieldName = $publicFieldName;');
      return sb.toString();
    }).join('\n');
  }

  String get _defaultPrivateConstructor {
    final sb = new StringBuffer();
    sb.write('\t$name({');
    var i = 0;
    var len = fields.keys.length - 1;
    fields.keys.forEach((key) {
      final f = fields[key];
      final publicFieldName =
          fixFieldName(key, typeDef: f, privateField: false);
      _addTypeDef(f, sb);
      sb.write(' $publicFieldName');
      if (i != len) {
        sb.write(', ');
      }
      i++;
    });
    sb.write('}) {\n');
    fields.keys.forEach((key) {
      final f = fields[key];
      final publicFieldName =
          fixFieldName(key, typeDef: f, privateField: false);
      final privateFieldName =
          fixFieldName(key, typeDef: f, privateField: true);
      sb.write('this.$privateFieldName = $publicFieldName;\n');
    });
    sb.write('}');
    return sb.toString();
  }

  String get _defaultConstructor {
    final sb = new StringBuffer();
    sb.write('\t$name({');
    var i = 0;
    var len = fields.keys.length - 1;
    fields.keys.forEach((key) {
      final f = fields[key];
      final fieldName =
          fixFieldName(key, typeDef: f, privateField: privateFields);
      sb.write('this.$fieldName');
      if (i != len) {
        sb.write(', ');
      }
      i++;
    });
    sb.write('});');
    return sb.toString();
  }

  String get _mapParseFunc {
    final sb = new StringBuffer();
    sb.write('\t$name');
    sb.write('.fromMap(Map<String, dynamic> map) {\n');
    fields.keys.forEach((k) {
      sb.write('\t\t${fields[k].mapParseExpression(k, privateFields)}\n');
    });
    sb.write('\t}');
    return sb.toString();
  }

  String get _jsonGenFunc {
    final sb = new StringBuffer();
    sb.write(
        '\tMap<String, dynamic> toMap() {\n\t\tfinal Map<String, dynamic> data = new Map<String, dynamic>();\n');
    fields.keys.forEach((k) {
      sb.write('\t\t${fields[k].toMapExpression(k, privateFields)}\n');
    });
    sb.write('\t\treturn data;\n');
    sb.write('\t}');
    return sb.toString();
  }

  String get _typeList {
    return fields.keys.map((key) {
      final f = fields[key];
      final fieldName =
          fixFieldName(key, typeDef: f, privateField: privateFields);
      final sb = new StringBuffer();
      sb.write('\t');
      sb.write('"$fieldName": "');
      _addTypeDef(f, sb);
      sb.write('",');
      return sb.toString();
    }).join('\n');
  }

  String get _foreignKeys {
    return _customization.foreignKeys.keys.map((key) {
      final sb = new StringBuffer();
      sb.write('\t');
      sb.write('"${camelCaseFirstLower(key)}": "');
      sb.write(_customization.foreignKeys[key]);
      sb.write('",');
      return sb.toString();
    }).join('\n');
  }

  String get _index => _customization.index.map((map) {
        return '  {' +
            map.keys.map((key) {
              final sb = new StringBuffer();
              sb.write('"${camelCaseFirstLower(key)}": "');
              sb.write(map[key]);
              sb.write('",');
              return sb.toString();
            }).join('') +
            '},\n';
      }).join('');

  String get _customSetters {
    final sb = new StringBuffer();
    sb.write("\n\t String get name => '${snakeCase(name)}';");
    if (_customization != null) {
      if (_customization.primaryKey.isNotEmpty)
        sb.write(
            "\n\tString get primaryKey => '${_customization.primaryKey}';");
      sb.write("\n\tMap<String, String> get typeMap => {");
      sb.write("\n$_typeList\n};\n");
      if (_customization.noUpdate.isNotEmpty) {
        sb.write("\n\tList<String> get noUpdate => [");
        _customization.noUpdate.forEach((field) {
          sb.write("\n\t\t'${camelCaseFirstLower(field)}',");
        });
        sb.write("\n\t\t];\n");
      }
      if (_customization.foreignKeys.isNotEmpty) {
        sb.write("\n\tMap<String, String> get foreginKeys => {");
        sb.write("\n$_foreignKeys\n};\n");
      }
      if (_customization.index.isNotEmpty) {
        sb.write("\n\tList<Map<String, String>> get index => [\n");
        sb.write(_index);
        sb.write('];\n');
      }
    }
    return sb.toString();
  }

  String toString() {
    if (privateFields) {
      return 'class $name {\n$_fieldList\n\n$_defaultPrivateConstructor\n \n$_customSetters\n\n$_gettersSetters\n\n$_mapParseFunc\n\n$_jsonGenFunc\n}\n';
    } else {
      return 'class $name {\n$_fieldList\n\n$_defaultConstructor\n\n$_customSetters\n\n$_mapParseFunc\n\n$_jsonGenFunc\n}\n';
    }
  }
}
