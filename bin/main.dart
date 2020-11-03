import 'dart:io';
import 'package:args/args.dart';
import '../lib/users_admin.dart' as users;
import '../lib/schema.dart' as schema;
import 'package:mongolib/src/utils.dart';

/// Command line tool to manage admins,
/// model schema, import data
/// backup and restore models
///
///
void main(List<String> arguments) async {
  final parsedArgs = argParser(arguments);
  users.Action userAction = parsedArgs['userAction'];
  schema.Action schemaAction = parsedArgs['schemaAction'];

  if (userAction != null) {
    await users.usersAdmin(userAction, parsedArgs['results']);
  } else {
    await schema.schemaAdmin(schemaAction, parsedArgs['results']);
  }
}

Map<String, dynamic> argParser(List<String> arguments) {
  final parser = ArgParser(allowTrailingOptions: true);
  parser.addSeparator('Global Arguments:');
  parser.addFlag('help',
      abbr: 'h',
      help: 'Print this usage information',
      defaultsTo: false,
      negatable: false);
  parser.addOption('user',
      abbr: 'u', help: 'login username.', valueHelp: 'String');
  parser.addOption('password',
      abbr: 'p', help: 'login password.', valueHelp: 'String');
  parser.addOption('serverHome',
      abbr: 's', help: 'Dart Mongoserver home .', valueHelp: 'String');
  parser.addSeparator('Schema Actions:');
  parser.addOption(
    'addModel',
    help: 'Add model to server. Filename or JSON string of the model',
    valueHelp: 'filename || JSON',
  );
  parser.addOption(
    'modifyModel',
    help:
        'Modify model schema. Filename or JSON string.Please backup model and data before.',
    valueHelp: 'filename || JSON',
  );
  parser.addOption(
    'dropModel',
    help: 'Name of the model and data to be dropped.',
    valueHelp: 'String',
  );
  parser.addOption(
    'backupModel',
    help: 'Backs up the model and data',
    valueHelp: 'String',
  );
  parser.addOption(
    'restoreModel',
    help: 'restore model and data previously backed up.',
    valueHelp: 'String',
  );
  parser.addOption(
    'import',
    abbr: 'i',
    help:
        'name of  import file. Allowed types: JSON, CSV or Google Firestore export files',
    valueHelp: '<filename>',
  );
  parser.addFlag('registerModel',
      abbr: 'r',
      defaultsTo: false,
      negatable: false,
      help: 'Register the model schema from import file structure.');
  parser.addSeparator('User Admin Actions:');
  parser.addOption(
    'addAdmin',
    abbr: 'a',
    help: 'Add a new user as admin. Add Roles after user\'s email, separated by **:** Roles are seprated by **,**',
    valueHelp: 'String:roles',
  );
  parser.addOption(
    'modifyAdmin',
    abbr: 'm',
    help: 'Update a user.Username can\'t be modififed',
    valueHelp: 'JSON',
  );
  parser.addOption('changePassword',
      abbr: 'c', help: 'Change an admin\'s own password.', valueHelp: 'String');
  parser.addOption(
    'deleteAdmin',
    abbr: 'd',
    help: 'Delete an Admin user.',
    valueHelp: 'String',
  );
  parser.addFlag('listAdmin',
      abbr: 'l', help: 'list admins.', negatable: false, defaultsTo: false);

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (e) {
    print('\n${(e.toString())}\n');
    printUsage(parser);
  }
  ;

  if (results['help']) {
    printUsage(parser);
  }
  ['user', 'password'].forEach((option) {
    if (results[option] == null) {
      print('\nUser and password are required\n');
      print(parser.usage);
      exit(0);
    }
  });

  users.Action userAction;
  schema.Action schemaAction;
  for (int i = 0; i < users.Action.values.length; i++) {
    if (results[describeEnum(users.Action.values[i])] != null) {
      userAction = users.Action.values[i];
      break;
    }
  }

  for (int i = 0; i < schema.Action.values.length; i++) {
    if (results[describeEnum(schema.Action.values[i])] != null) {
      schemaAction = schema.Action.values[i];
      break;
    }
  }

  if (schemaAction == null && userAction == null) {
    print('\nNo action was provided. Choose one of Schema or Usage Actions\n');
    printUsage(parser);
  }
  // we should get at least one command

  return {
    'results': results,
    'userAction': userAction,
    'schemaAction': schemaAction,
  };
}

void printUsage(ArgParser parser) {
  final exec = Platform.script.path.split('/').last;
  print('\nUsage: $exec <global arguments> <action> <argument>\n');
  print(parser.usage);
  exit(0);
}
