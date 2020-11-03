import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:dart_style/dart_style.dart';
import 'package:args/args.dart';
import 'package:mongoadmin/json_to_dart/helpers.dart';
import 'package:mongoadmin/admin_common.dart';
import 'package:mongoadmin/import.dart';
import 'package:mongoclient/mongoclient.dart';
import 'package:mongolib/src/utils.dart';

enum Action {
  addModel,
  backupModel,
  dropModel,
  modifyModel,
  import,
  restoreModel,
}

void schemaAdmin(
  Action action,
  ArgResults results,
) async {
  print('MongoDb Admin Version 0.0.1');
  print('Schema Processor');
  final io = Io(home: results['serverHome']);
  List<Map<String, dynamic>> index;
  String model;
  final db = MongoDbClient();
  final response = await db.authenticate(
      results['user'], results['password'], AuthAction.signInWithPassword);
  if (response.status != 200) {
    print('Authorization failed: ' + response.body);
    return;
  }
  final auth = json.decode(response.body)['user'];
  if (!auth['isAdmin']) {
    print('Authorization failed');
    return;
  }
  final optionArg = results[describeEnum(action)];
  final register = results['updateschema'] ?? false;
  switch (action) {
    case Action.dropModel:
      if (!io.exists('models', optionArg)) {
        print('Error: $optionArg not found.');
        return;
      }
      // if dropping always backup
      //return await dropModel(io, optionArg, auth, backup: true);
      final filename = snakeCase(optionArg);
      final code = io.readFile('models', filename);
      final pattern = r"export '$filename.dart'\n";
      io.saveFile('models', 'index', code.replaceFirst(pattern, ''));
      io.saveFile('models/backup/${DateTime.now().toString().substring(0, 10)}',
          filename, io.readFile('models', filename));
      io.delete('models', filename);
      return;
    case Action.import:
      return await import(io, optionArg, register: register);
    case Action.backupModel:
      return backupData(io, model);
    case Action.restoreModel:
      return await restoreData(io, optionArg);
    case Action.modifyModel:
      String jsonData = io.getJson(optionArg);
      if (jsonData == null) {
        print('$optionArg must either be a file or a JSON String');
        return;
      }
      final rawJson = Map<String, dynamic>.from(json.decode(jsonData));
      model = rawJson['collectionName'];
      index = rawJson['index'];
      if (!io.exists('models', model)) {
        print('Error: $model not found.');
        return;
      }
      // optional backup
      if (results['backup']) {
        await backupData(io, model);
      }
      break;
    case Action.addModel:
      String jsonData = io.getJson(optionArg);
      if (jsonData == null) {
        print('$optionArg must either be a file or a JSON String');
        return;
      }
      final rawJson = Map<String, dynamic>.from(json.decode(jsonData));

      model = snakeCase(rawJson['collectionName']);
      index = rawJson['index'];

      if (io.exists('models', model)) {
        print('Error: $model is already registered. Can not add');
        return;
      }

      break;
  }

  final map = generateDartClass(
    optionArg,
  );
  io.saveFile('models', snakeCase(map['model']), map['code']);
  registerModel(io, map['model']);
  await checkIndex(db, model, index);
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

Future<void> restoreData(Io io, String model) async {
  final modelFilename = '${snakeCase(model)}.dart';
  final backupfiles = io.glob('backup/*/$modelFilename');
  if (backupfiles.isEmpty) {
    print('---> Info - No backups found for $model.');
    return;
  }
  final dates = backupfiles
      .where((e) => RegExp(r'^.*/\d{4}-\d{2}-\d{2}$').hasMatch(e))
      .toList();
  dates.sort();
  final backupDate = dates.last;
  print(
      '---> Info - $backupDate is the latest available backup.\npress Enter to contine or ^C to end');
  stdin.readLineSync();

  final backupPath = 'backup/$backupDate';
  // restore model, data, check if models/index has an entry for the file - add it if required
  final String modelContents = io.readFile(backupPath, modelFilename);
  io.saveFile(
    'models',
    modelFilename,
    io.readFile(backupPath, modelContents),
  );
  final modelSchema = json.decode(modelContents);

  print('---> Ok - schema restored.');
  final index = io.readFile('models', 'index');
  final sb = StringBuffer();
  if (!index.contains(modelFilename)) {
    sb.write(index);
    sb.write("export '$modelFilename';\n");
    print(sb.toString());
    io.saveFile('models', 'index', sb.toString());

    print('---> Ok - Registration added.');
  } else {
    print('---> Ok - Registration checked.');
  }
  final db = MongoDbClient();
  await db.drop(model);
  print('--->      dropped existing $model ');
  stdout.write('---> Ok - restoring data... ');
  final documents = json.decode(io.readFile(backupPath, model));
  await db.createDocuments(model, documents);
  stdout.writeln('done!');
  print('---> Info - Creating Indexes');
  final response = await checkIndex(db, model, modelSchema['index']);
  if (response['ok'] == 1.0) {
    print('---> Ok - index done: ${response["result"]}. ');
  } else {
    print('---> Info -> ${response["result"]}');
  }
}

Future<void> backupData(Io io, String model) async {
  final backupDirectory =
      'backup/' + DateTime.now().toString().substring(0, 10);
  final modelFilename = '${snakeCase(model)}.dart';

  io.saveFile(
    backupDirectory,
    modelFilename,
    io.readFile('models', modelFilename),
  );
  print('---> Ok - Schema backedup.');
  final dataFile = File(io.filePath(backupDirectory, model));
  final dataSink = dataFile.openWrite();
  stdout.write('--> Backing up data ');
  final db = MongoDbClient();
  final count = await db.count(model);
  int written = 0;
  int percentage = 0;
  int skip = 0; // start at first record
  const int limit = 100; // get at most limit no. of records
  bool eof = false;

  while (!eof) {
    final response =
        await db.find(model, filters: {"limit": limit, 'skip': skip});
    if (response.status != HttpStatus.ok) {
      eof = true;
      continue;
    }
    final records = json.decode(response.body);
    skip += min<int>(records.length, limit);
    records.forEach((element) {
      dataSink.write(
        '${json.encode(element)}\n',
      );
      written++;
      int newpercentage = (((written / count) * 100) ~/ 10) - percentage;
      if (newpercentage > 0) {
        stdout.write(' $newpercentage% ');
      }
      percentage = ((written / count) * 100) ~/ 10;
    });
  }
  dataSink.close();
  await dataSink.done;
  stdout.writeln(' 100%!');
}
