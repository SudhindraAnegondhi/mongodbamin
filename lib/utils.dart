import 'dart:io';
import 'package:mongolib/src/utils.dart';

final url = 'http://localhost:8888';


String camelCase(String text) {
  String capitalize(Match m) =>
      m[0].substring(0, 1).toUpperCase() + m[0].substring(1);
  String skip(String s) => "";
  return text.splitMapJoin(new RegExp(r'[a-zA-Z0-9]+'),
      onMatch: capitalize, onNonMatch: skip);
}

String snakeCase(String text) {
  var tl = '';
  camelCaseFirstLower(text).split('').forEach(
      (c) => tl += RegExp(r'[A-Z]').hasMatch(c) ? '_' + c.toLowerCase() : c);
  return tl;
}

String camelCaseFirstLower(String text) {
  final camelCaseText = camelCase(text);
  final firstChar = camelCaseText.substring(0, 1).toLowerCase();
  final rest = camelCaseText.substring(1);
  return '$firstChar$rest';
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


void generateEmail(String username, String password, List<Role> roles) {
  final sb = StringBuffer();
  sb.write('Dear $username:\n');
  sb.write('You have been added as a mongoserver admin.\n\n');
  sb.write('Your assigned roles are as follows:\n');
  roles.forEach((role) {
    sb.write('\t${describeEnum(role)}\n');
  });
  sb.write('\n\nYour account has been created with password: $password\n\n');
  sb.write(
      'Please change the password at your earliest.\n\nDart MongoAdmin Team');
  print(sb.toString());
}
