import 'dart:convert';
import 'package:args/args.dart';
import 'generate_password.dart';
import 'package:flexprint/flexprint.dart';
import 'package:mongoclient/mongoclient.dart';
import 'package:mongolib/mongolib.dart';
import 'package:mongolib/src/new_user.dart';
import 'package:mongolib/src/utils.dart';
import 'utils.dart';

enum Action {
  addAdmin,
  changePassword,
  deleteAdmin,
  modifyAdmin,
  listAdmin,
}
Future<void> adminList(MongoDbClient db) async {
  final sb = FlexPrint();
  // heading
  sb.horizontalLine();
  sb.write('User Name', flex: 3);
  sb.write('Roles\n', flex: 4, alignment: Alignment.center);
  sb.write(' ', flex: 3);
  Role.values.forEach((role) {
    sb.write(describeEnum(role), alignment: Alignment.center);
  });
  sb.write('\n');
  sb.horizontalLine();
  final response = await db.find('user', filters: {'isAdmin': true});
  if (response.status != 200) {
    print('---> Error: ' + response.body);
    return;
  }
  final users = json.decode(response.body);
  users.forEach((user) {
    sb.write(user['username'], flex: 3);
    Role.values.forEach((role) {
      String found = '-';
      (user['roles'] ?? <Role>[]).forEach((r) {
        if (r == describeEnum(role)) {
          found = 'Yes';
        }
      });

      sb.write(found, alignment: Alignment.center);
    });
    sb.write('\n');
  });
}

Future<void> usersAdmin(
  Action action,
  ArgResults results,
) async {
  // try {
  final MongoDbClient db = MongoDbClient();
  final response = await db.authenticate(
      results['user'], results['password'], AuthAction.signInWithPassword);
  Map<String, dynamic> authUser;
  if (response.status == 200) {
    authUser = response.body['user'];
  }
  List<String> parts;
  Map<String, dynamic> existingDocument;
  String username;

  print('MongoDb Admin Version 0.0.1');
  print('User Admin');

  final List<Role> roles = [];
  if (action == Action.addAdmin ||
      action == Action.deleteAdmin ||
      action == Action.modifyAdmin) {
    parts = results[describeEnum(action)]?.split(':');
    if (parts == null) {
      print('Username is required');
      return;
    }
    username = parts[0].toString() ?? '';

    if (username == authUser[results['user']] &&
        action != Action.changePassword) {
      print('An admin may not make changes to their own account');
      return;
    }

    if ((parts?.length ?? 0) == 2) {
      parts[1].split(',').forEach((role) {
        roles.add(stringToEnum(role, Role.values));
      });
    }
    final response = await db.findOne('user', 'username', username);
    existingDocument =
        response.status == 200 ? json.decode(response.body) : null;
  }
  switch (action) {
    case Action.addAdmin:
      if (existingDocument != null) {
        print('$username exists!');
        return;
      }
      if (username != null &&
          !RegExp(r'^[a-zA-Z\._\-0-9]+@[a-zA-Z\._\-0-9]+\.[a-zA-Z]{2,3}$')
              .hasMatch(username)) {
        print('Username must be an email address');
        return;
      }

      final password = generatePassword(true, true, true, true, 8);
      final userMap = newUser(
        username,
        password,
        true,
        roles: roles,
      );

      final response = await db.save('user', userMap);

      if (response.status == 200) {
        generateEmail(username, password, roles);
      } else {
        print('Error: $username not added');
      }
      break;
    case Action.changePassword:
      final password = results.command[describeEnum(action)];
      if (password == null) {
        print('New password is required');
        return;
      }
      final userMap = authUser;
      userMap['hashedPassword'] = generatePasswordHash(
        password,
        authUser['salt'],
      );
      final response = await db.save('user', userMap);
      if (response.status == 200) {
        print('---> Ok - password changed.');
      } else {
        print('---> Error - password not changed.');
      }
      break;
    case Action.deleteAdmin:
      if (authUser['roles'].contains(Role.userAdmin) ||
          authUser['roles'].contains(Role.all)) {
        final response = await db.remove('user', {'username': username});
        //await database.collection('user').remove({'username': username});
        if (response.status == 200) {
          print('---> Ok - Admin deleted.');
        } else {
          print('---> Error - Admin not deleted.');
        }
      } else {
        print('---> Error - not authorized.');
      }
      break;
    case Action.listAdmin:
      await adminList(db);
      break;

    case Action.modifyAdmin:
      try {
        final userRecord = json.decode(results['updateAdmin']);
        // only admin, firstName, lastName allowed to be changed
        ['isAdmin', 'firstName', 'lastName'].forEach((key) {
          existingDocument[key] = userRecord[key] ?? existingDocument[key];
        });
        final user = User.fromMap(existingDocument);
        user.roles = roles;
        final response = await db.save('user', user.toMap());
        if (response.status == 200) {
          print('---> Ok - User updated.');
        } else {
          print('---> Error - User not changed.');
        }
      } catch (e) {
        print('---> Error ' + e.toString());
      }
      break;
  }
  /*
  } catch (e) {
    print('Error: ${e.toString()}');
  }
  */
}
