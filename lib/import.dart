import 'dart:io';
import 'dart:convert';
import 'package:dart_console/dart_console.dart';
import 'package:inflection2/inflection2.dart';
//import 'package:http/http.dart' as http;
import './json_to_dart/helpers.dart';
import './admin_common.dart';
import 'package:mongoclient/mongoclient.dart';

Future<void> import(
  Io io,
  //String username,
  // String password,
  String path, {
  bool register = false,
}) async {
  final importFile = File(io.filePath(null, path));
  final parts = path.split('/');
  final basename = singularize(parts.last.split('.').first);
  final model = camelCase(basename);
  final console = Console();
  console.clearScreen();
  print('--> Info - importing $basename');
  List<Map<String, dynamic>> documents = [];
  int documentsSaved = 0;
  String record = '';
  bool checkedSchema = false;

  final MongoDbClient db = MongoDbClient();

  if (!register) {
    final response = await db.allowModel(camelCaseFirstLower(model));
    if (response.statusCode != HttpStatus.ok) {
      print('Allow failed: ${response.body} ');
      return;
    }
  }
  final lines = importFile.readAsLinesSync();
  final ImportFileType fileType = importFileType(lines);
  int docs = 0;
  final fields = fileType == ImportFileType.csv ? lines[0].split(',') : null;

  /// processes the collected record
  /// adds to buffer, creates model if regsterFlag is set
  /// writes buffer to db on buffer limit, empties the buffer
  Future<void> processRecord() async {
    final document =
        Map<String, dynamic>.from(json.decode(stripTrailingComma(record)));
    docs++;
    document.removeWhere((key, value) => key == 'id');
    record = '{';
    if (register && !checkedSchema) {
      checkedSchema = true;
      final indexList = checkModelPresent(io, basename, document);
      if (indexList != null) {
        documents = [
          document,
        ];

        await checkIndex(db, model, indexList);
        final count = await saveDocuments(db, model, documents);
        documentsSaved += count;
        documents = [];
      }
    } else {
      documents.add(document);
    }

    if (documents.length == 200) {
      documentsSaved += await saveDocuments(db, model, documents);
      //console.cursorPosition = Coordinate(4, 1);
      //console.write(documentsSaved.toString());
      documents = [];
      //docs = 0;
    }
  }

  lines.forEach((line) async {
    switch (fileType) {
      case ImportFileType.firestore:
        if (RegExp(r'^\s{0,2}\"[0-9,a-z,A-Z]+\"\s*:\s*\{\s*$').hasMatch(line)) {
          if (record.isNotEmpty) {
            await processRecord();
          }
          record = '{';
        } else {
          record += line;
        }
        break;
      case ImportFileType.json:
        record = line;
        await processRecord();
        break;
      case ImportFileType.csv:
        Map<String, dynamic> recMap = {};
        final values = line.split('.');
        if (fields.length != values.length) {
          print('Fields and Values mismatch: $line');
          break;
        }
        for (int i = 0; i < fields.length; i++) {
          recMap[fields[i]] = values[i];
        }
        documents.add(recMap);
        docs++;
        if (documents.length == 200) {
          documentsSaved += await saveDocuments(db, model, documents);
        }
    }
  });

  documentsSaved += await saveDocuments(db, model, documents);
  print('\nTotal documents read: $docs');
  print('Total documents saved: $documentsSaved');
}

enum ImportFileType {
  firestore,
  json,
  csv,
}

ImportFileType importFileType(List<String> lines) {
  // check if it is a CSV file. The first line must be a header
  if (RegExp(r'^[a-z,A-Z][0-9,_,a-z,A-Z]*[\,]?$').hasMatch(lines[0])) {
    return ImportFileType.csv;
  }
  // may be json or not. let's try to decode and see
  String line = lines.firstWhere((l) => l.contains('{'), orElse: () => null);
  if (line == null) {
    return null;
  }
  try {
    json.decode(line);
    return ImportFileType.json;
  } catch (e) {
    if (RegExp(r'^\s{0,2}\"[0-9,a-z,A-Z]+\"\s*:\s*\{\s*$').hasMatch(line)) {
      return ImportFileType.firestore;
    }
  }
  return null;
}
