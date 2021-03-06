import 'dart:io';
import 'dart:convert';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:mongoclient/mongoclient.dart';
//import 'package:http/http.dart' as http;
import 'json_to_dart/model_generator.dart';
import 'utils.dart';

//final url = 'http://localhost:8888';

Future<Map<String, dynamic>> checkIndex(
  MongoDbClient db,
  String model,
  List<Map<String, dynamic>> indexList,
  //Map<String, dynamic> headers,
) async {
  if (indexList == null || indexList.length == 0) {
    return {'ok': -1, 'result': 'No indexes specified'};
  }
  List<String> indexes = [];

  indexList.forEach((index) async {
    /*
    final response = await http.post(
      '$url/createindex/$model',
      headers: headers,
      body: json.encode(index),
    );
    */
    final response = await db.createIndex(
      camelCaseFirstLower(model),
      name: model,
      keys: index['keys'],
      unique: index['unique'],
      partialFilterExpression: index['partialFilterExpression'],
    );
    indexes.add(index['name'] + response.status != 200 ? 'failed' : 'created');
  });
  return {'ok': 1, 'body': indexes};
}

void registerModel(Io io, String _model) {
  final className = camelCase(_model);
  final model = snakeCase(_model);
  print('Registering model: $model..');
  final sb = StringBuffer();
  try {
    final index = io.readFile('models', 'index');
    if (!index.contains(model)) {
      sb.write(index);
      sb.write("export '$model.dart';\n");
      io.saveFile('models', 'index', sb.toString());
      print('...done!\n\n');
    } else {
      print('$model is already registered');
      return;
    }
  } catch (e) {
    print("\n\n****Index not found. Generating Register and Index****\n");
    return _fixRegister(io);
  }

  sb.clear();
  String code = io.readFile('base', 'model_register');
  if (code.contains(className)) {
    // already in models register
    return;
  }
  int index = code.indexOf('//!important');
  if (index == -1) {
    return _fixRegister(
        io); // recreate the model_register.dart, as it's corrupted
  }
  sb.write(code.substring(0, index - 1));
  sb.write("\n'$model': $className(),\n");
  sb.write(code.substring(index));
  final formatter = DartFormatter();
  final newCode = formatter.format(sb.toString());
  io.saveFile('base', 'model_register.dart', newCode);
}

void _fixRegister(Io io) {
  print('**** Scanning all registered models....');
  final modelsDirPath = '${io.home}/lib/models';
  final modelsDir = Directory(modelsDirPath);
  List<Map<String, dynamic>> models = [];

  modelsDir.listSync(recursive: false, followLinks: false).forEach((entry) {
    final file = entry.path.split('/').last.toLowerCase();
    if (!file.contains('index')) {
      final className = camelCase(file.split('.').first);
      final route = camelCaseFirstLower(className);
      print('Found $className');
      models.add({
        'exportPath': "export '$file';\n",
        'route': "\t\t'$route': $className(),\n",
      });
    }
  });

  print('Writing out model_register');
  final sb = StringBuffer();
  sb.write('// This file is generated please do not edit this file\n\n');
  sb.write("import 'package:mongoserver/models/index.dart';\n\n");
  sb.write('class ModelRegister {\n');
  sb.write('\tMap<String, dynamic> _models = {\n');
  models.forEach((model) {
    sb.write(model['route']);
  });
  sb.write('//!important - do not remove required for program generation\n');
  sb.write('\t};\n\n');
  sb.write("dynamic instance(String model) => _models[model];\n}\n");
  io.saveFile("base", 'model_register', sb.toString());
  print('....done!\n\n');

  print('Writing out index');
  sb.clear();

  models.forEach((model) {
    sb.write(model['exportPath']);
  });
  io.saveFile('models', 'index', sb.toString());
  print('**** done fix register***');
}

List<Map<String, dynamic>> checkModelPresent(
  Io io,
  String basename,
  Map<String, dynamic> fields,
) {
  final Map<String, dynamic> schemaJson = {};
  final modelFilename = basename + '.dart';
  final model = camelCase(basename);
  if (io.exists('models', modelFilename)) {
    print('$model is already registered.');
    return null;
  }
  schemaJson['collectionName'] = snakeCase(model);
  schemaJson['fields'] = fields;
  // lets get primary key
  final fieldList = fields.keys.toList();
  final chooser = Chooser<String>(fieldList, message: 'Choose: ');
  final primaryKey = chooser.chooseSync();
  if (primaryKey != null) {
    schemaJson['primaryKey'] = primaryKey;
    schemaJson['index'] = [
      {
        'name': 'meta',
        'keys': {primaryKey: 1},
        'unique': true
      }
    ];
  }
  String jsonData = json.encode(schemaJson);
  Map<String, dynamic> map = generateDartClass(jsonData);
  io.saveFile('models', modelFilename, map['code']);
  registerModel(io, model);
  return schemaJson['index'];
}

Map<String, dynamic> generateDartClass(String jsonData) {
  final data = json.decode(jsonData) as Map<String, dynamic>;
  final dateFields = data['dateFields'] ?? <String>[];
  final model = data['collectionName'];
  final primaryKey = data['primaryKey'];
  final noUpdate = data['noUpdate'] ?? [];
  final index = data['index'] ?? {};
  final foreignKeys = data['foreignKeys'] ?? {};
  final fields = data['fields'];
  final classGenerator = new ModelGenerator(
    model,
    false,
    dateFields,
    primaryKey,
    foreignKeys,
    noUpdate,
    index,
  );
  DartCode dartCode = classGenerator.generateDartClasses(json.encode(fields));
  return {'model': model, 'code': dartCode.code};
}

Future<int> saveDocuments(
  MongoDbClient db,
  String model,
  List<Map<String, dynamic>> documents,
  // Map<String, dynamic> headers,
) async {
  final response = await db.createDocuments(camelCaseFirstLower(model), documents);
  return response.statusCode == 200 ? documents.length : 0;
  /*
  return Future.sync(() {
    if (documents.isEmpty) {
      return 0;
    }
    return http
        .post(
          '$url/${camelCaseFirstLower(model)}',
          headers: headers,
          body: json.encode(documents),
        )
        .then((response) =>response.statusCode == 200 ? documents.length : 0);
  });
  */
}

String stripTrailingComma(String str) {
  if (str == null || str.length == 0) {
    return str;
  }
  for (int i = str.length - 1; i >= 0; i--) {
    if (RegExp(r'\s').hasMatch(str[i])) {
      continue;
    } else {
      if (str[i] == ',') {
        return i > 0 ? str.substring(0, i) : null;
      }
      break;
    }
  }
  return str;
}

class Chooser<T> {
  final List<T> choices;
  final String message;
  Chooser(this.choices, {this.message = 'Choose: '});

  dynamic chooseSync() {
    if (choices?.isEmpty ?? true) {
      return null;
    }
    final sb = StringBuffer();
    sb.writeln('Select a primary key:\n');
    sb.write('\n');
    for (int i = 0; i < choices.length; i++) {
      sb.writeln('  [${(i + 1).toString()}] ${choices[i].toString()}');
    }
    sb.writeln('   Enter a number to select or [q] for none');
    stdout.write(sb.toString());
    stdout.write(message);
    int choice = 2; // for now
    while (choice == null) {
      final input = stdin.readLineSync();
      if (input == 'q') {
        print('no primary key');
        return null;
      }
      choice = int.tryParse(input);
      if (choice != null && (choice < 0 || choice > choices.length)) {
        choice = null;
      }
    }
    print(choice != null
        ? ' ${choices[choice - 1]} selected.\n'
        : ' Selected None\n');
    return choice == null ? null : choices[choice - 1];
  }
}

/// Wrapper class for File IO operations.
/// Provides all file operations the server home
/// directory. Checks the supplied path to ensure that the
/// server directory is named  'mongoserver'.

const _projectDir = 'mongoserver';

class Io {
  String _home;
  Io({String home}) : _home = __scriptPath(home);

  String get home => _home;

  static String __scriptPath(String home) {
    if (home == null) {
      /*
      var script = Platform.script.toString();
      if (script.startsWith("file://")) {
        script = script.substring(7);
      } else {
        final idx = script.indexOf("file:/");
        script = script.substring(idx + 5);
      }
      print('script: $script');
      */
      final cwd = Directory.current.path;
      if (!cwd.endsWith(_projectDir)) {
        print('Serverhome path must point to MongoServer directory');
        exit(1);
      }
      //print(script.substring(0, index + _projectDir.length));

      return cwd; //script.substring(0, index + _projectDir.length);
    }

    return home;
  }

  /// Combines user supplied path and file name, filling in  required
  /// path if user has not supplied a path. Assigns default '.dart' extension
  /// to filename if none is suupplied.
  String filePath(String path, String filename) {
    if (filename.contains('/') && path == null) {
      // user supplied the path. Independent of server home
      return filename;
    }
    return path?.isEmpty ?? true
        ? _home + '/' + (filename.contains('.') ? filename : '$filename.dart')
        : "$_home/lib/$path/${filename.contains('.') ? filename : '$filename.dart'}";
  }

  bool exists(String path, String filename) =>
      File(filePath(path, filename)).existsSync();

  void delete(String path, String filename) =>
      File(filePath(path, filename)).deleteSync();

  String readFile(String path, String filename) =>
      new File(filePath(path, filename)).readAsStringSync();

  void saveFile(String path, String filename, String contents) =>
      File(filePath(path, filename))
          .writeAsStringSync(contents, mode: FileMode.write);

  List<String> glob(String pattern) =>
      Glob("$_home/lib/$pattern").listSync().map((e) => e.path).toList();

  /// Examines a command line arguement is
  /// a command line JSON string returns  return json
  /// OR A model or file name --> returns the string if it doesn't have
  /// .json type. Could be a modelname or a filename.
  /// OR. A Schema JSON file.----> Checks the file structure amd returns JSON map
  /// if found a valid schema JSON file or throws error
  dynamic getJson(String rawData) {
    try {
      if (RegExp(r'^{\s*"collectionname"\s*:\s*"[^"]+".*}$')
          .hasMatch(rawData)) {
        return rawData; // command line json
      }
      if (rawData.split('.').last != 'json') {
        return rawData; // perhaps a filename. Who knows?
      }

      if (exists(null, rawData)) {
        final str = json.decode(readFile(null, rawData));
        if (RegExp(r'^{\s*"collectionname"\s*:\s*"[^"]+".*}$').hasMatch(str)) {
          return json.decode(rawData); // command line json
        }
        print('$rawData is not a valid Schema file');
      }
    } catch (e) {
      print('Error: ${e.toString()}');
    }
    return null;
  }
}
