# MongoAdmin

- [MongoAdmin](#mongoadmin)
  - [Introduction](#introduction)
  - [Usage](#usage)
  - [Install](#install)
    - [Add PATH to env](#add-path-to-env)
  - [Admin Management](#admin-management)
    - [Add Admin](#add-admin)
      - [Roles](#roles)
    - [Change Password](#change-password)
    - [Add/Modify Roles](#addmodify-roles)
    - [Delete Admin](#delete-admin)
    - [List Admins](#list-admins)
  - [Schema Management](#schema-management)
    - [Schema JSON to Dart Class](#schema-json-to-dart-class)
      - [JSON Schema Object Structure](#json-schema-object-structure)
    - [Add Schema Model](#add-schema-model)
    - [Modify Schema Model](#modify-schema-model)
    - [Drop Schema Model](#drop-schema-model)
    - [Restore from Backup](#restore-from-backup)
  - [Import data](#import-data)
    - [Supported formats](#supported-formats)

## Introduction

Mongoadmin is a command line utility allowing the management of admins, adding, modifying data models served by _mongoserver_. Only users with Admin privelege may use this app.

## Usage

```sh
dart bin/main.dart  --help

Usage: main.dart <global arguments> <action> <argument>

Global Arguments:
-h, --help                              Print this usage information
-u, --user=<String>                     login username.
-p, --password=<String>                 login password.
-s, --serverHome=<String>               Dart Mongoserver home .

Schema Actions:
    --addModel=<filename || JSON>       Add model to server.
    --modifyModel=<filename || JSON>    Modify model schema.
    --dropModel=<String>                Name of the model and data to be dropped.
    --backupModel=<String>              Backs up the model and data
    --restoreModel=<String>             restore backed up model/data.
-i, --import=<<filename>>               Import  JSON/CSV/Firestore data.
-r, --registerModel                     Register imported model schema.

User Admin Actions:
-a, --addAdmin=<String:roles>           Add new admin,roles.
-m, --modifyAdmin=<JSON>                Modify admin.
-c, --changePassword=<String>           Change own password.
-d, --deleteAdmin=<String>              Delete an Admin user.
-l, --listAdmin                         List admins.
```

## Install

Please download the git repository.

```shell
$ git clone https://IndeDude@bitbucket.org/IndeDude/mongoadmin.git
cloaning in to 'mongoadmin'...
cd mongoadmin
$ pub get
Resolving dependencies...<omitted output>
$ sudo dart2native bin/mongoadmin.dart -o ../mongoserver/bin/mongoadmin
Generated: ../mongoserver/bin/mongoadmin
```

Change `../mongoserver` path if your server path is different.

### Add PATH to env

```sh
# assuming bash. You will need to make suitable changes
# depending om the shell
echo "export PATH=$PATH:<mongoserver path>/bin" >> ~/.bshrc
source ~/.bshrc
```

**Note**: If you choose to execute *mongoadmin* from any other directory except `mongoserver` directory, you must specify the server path with `-s path_to_mongoserver_directory`.

## Admin Management

**_serverAdmin:_**
All mongoserver installations are pre-configured with the **serverAdmin** user account with a default password - _changeme_. _It is strongly advised to change the password right away after installation, add a new admin with_ **roles: 'all**', before proceeding with oher admin tasks.

### Add Admin

The username must be a valid email address. The _roles_ of the new admin are specified by appending them to the admin's email address seperated by a "**:**".

#### Roles

The allowed roles are:

| Role          | Allowed Tasks                                              |
| ------------- | ---------------------------------------------------------- |
| **all**       | The Admin may perform any admin task, including add and delete admins, assign/revoke roles, add or modify schema                                 |
| **add**       | The admin is allowed to add new models in the schema but may not modify existing models. The admin is also not allowed to add/modify new Admins. |
| **modify**    | This role has the privileges of the **add** role, and may modify admin account.                                                                  |
| **userAdmin** | This role privileges of both **add** and **modify** roles, but may not modify or delete Admin accounts                                           |

---

**Please Note**: \*An admin may only assign roles equal or less to their own while adding/modifying admins.

---

```sh
$ mongoadmin --user adminemail.domain --password 12344%Aa --addAdmin newadmineamil.dom:userAdmin
---> OK - successfully added. Ask them to check their email.
```

### Change Password

An admin may change only their own password.

[Go to Top](#mongoadmin)

```sh
$ mongoadmin --user adminemail.domain --password 12344%Aa --changePassword Aa#%12345
---> OK - changed password.
```

### Add/Modify Roles

Any admin with `userAdmin` privilege can change the roles of any admin. An admin may not change their own roles, unless they are `serverAdmin`. The new roles
will replace the old rules in the admin's account.

**Please note**: To remove all roles (in effect, suspend the admin) enter a "**-**" in place of roles.

```sh
$ mongoadmin --user adminemail.domain --password 12344%Aa -roles modify
---> OK - role changed to modify
```

### Delete Admin

Any admin with `userAdmin` privilege remove an admin's account. An admin can not remove their own account. The `serverAdmin` account can not be deleted. T

```sh
$ mongoadmin  -deleteAdmin jdoe@cfil.com
---> OK - admin user deleted
```

### List Admins

```sh
$ mongoadmin --user adminemail.domain --password 12344%Aa -listAdmin
--------------------------------------------------------------------------------
User Name                                           Roles
                                     add        all      modify    userAdmin
--------------------------------------------------------------------------------
adminemail.dom                        -         Yes         -          -
atest@test.com                        -         Yes         -          -
```

[Go to Top](#mongoadmin)

## Schema Management

_mongoDb_ does not require pre-configured schema to store and retrieve objects. However that as they say, is no way to run a railroad. A server with no knowledge of it's data structure will find it impossible to maintain indexes, ensure that type validated data is stored and retrieved in a predictable manner.

Pre-configuring schema objects as required by _mongoserver_ allows the enforcement of primary keys, cascade deletes of dependent schema objects, type validation of all data stored and retrieved, manage indexes, imposition of a known structure on the data stored and retrieved so that the client applications know what to expect.

Admins can with suitable privileges can add, modify or delete Schema Models.

---

**CAUTION:**

**STOP _mongoserver_ BEFORE ANY SCHEMA CHANGE**
**AND RESTART SERVER AFTER THE CHANGE**

---

[Go to Top](#mongoadmin)

### Schema JSON to Dart Class

_mongoserver_ of course has the schema stored in Dart Classes. The admins to only provide a JSON object of the schema model and mongoadmin converts the JSON object to a dart class and add it in the appropriate directory under mongoserver/lib directory.

#### JSON Schema Object Structure

A Schema object may look like the following:

```json
{
  "collectionName": "specialWidgets",
  "primaryKey": "widgetname",
  "foreignKeys": { "product_id": "products", "supplier_id": "supplier" },
  "index": [
    {"name": "supplierwise", "keys": { "supplierId": 1, "lastUsed": -1}},
    {"name": "primary", "keys" :{"widgetname": 1}, "unique": true}
  ],
  "noUpdate": ["widgetname", "productId", "supplierId"],
  "dateFields": ["/lastUsed"],
  "fields": {
    "widgetName": "A widget name",
    "productId": "addfdf12",
    "supplierId": "adnfdfd",
    "description": "xxxx",
    "assemblyCode": "adfdfdfd",
    "quantityInStock": 24,
    "quantityOnOrder": 200,
    "price": 2987.56,
    "lastUsed": 454545008,
    "models": ["space scooter", "star worm", "necroorangetop"],
    "hasSubstitutes": false,
    "bomLink": "https://bom.acme.dfut/xxx%20xx"
  }
}
```

1. `collectionName` is the name of the model. The name should follow the normal dart varialbe identifier conventions governing class names.
2. `primaryKey` can be any of the model's fields. All primary keys are considered to be unique by mongoserver and are enforced at the server level as the database itself will not enforce the no duplicates rule.
3. `foreignKeys` is a map of foreign keys in the model and their associated collection names. Relationships (one2one, one2many, many2one) are not a part of mongodb and they are not being enforced at this point in time. In future it's expected that mongoserver will support this feature more completely.
4. `index` a map of index name and the field being indexed and the sort order (ascending/desceding) separated with a "**.**", from the field name.
5. `noUpdates` is a list of field names that should not be updated/changed after creation.
6. `dateFields` is a list of field _paths_ (starting at the top level as '/') of DateTime fields in the model. This is required currently because the JSON to Dart engine does not detect date fields correctly automatically.
7. `fields` The JSON map of the model. Nested maps are allowed.

`collectionName` and `fields` are required the rest are optional.

[Go to Top](#mongoadmin)

### Add Schema Model

Schema may be enterd on the command line or taken from a file. Schema JSON file must always be located in the serverhome directory.

```sh
# Schema stored in a file
$ mongoadmin  --user adminemail.domain --password 12344%Aa --addModel widget.json
---> OK - Model SpecialWidgets added to server.
```

_mongoadmin_ will look for the file `widget.json` in the `../mongoserver` directory.

### Modify Schema Model

Existing schema may be modified using this command. **Please backup the server/code and data BEFORE modifying by setting the --backup flag**

Only the fields requiring the change need to be entered. Fields can not be dropped as database may contain data. Use other tools to safely drop fields preserving the data. Fields with type changes may result in data loss as well. Data will be lost if the existing field type data can not be correctly converted to the new type.

The structure of the SCHEMA JSON object is the same as in **add**. Fields in the list will be matched against existing fields, if the field is new it will be added or data will be ported over to the new type if possible.

```sh
# Schema stored in a file, backup requested
$ mongoadmin  --user adminemail.domain --password 12344%Aa --modifyModel widget.json  --backupModel
---> Data backed up.
---> Model backed up.
---> Fields being modified:
  percentageDiscount int -> double: WARNING: Check the data
  address List<String, dynamic> -> {street: Sgitring,
  city: String, state: String, zipcode:
  String}: Mapped [0] to Street, [1] city...: WARNING: Check the data
---> Fields being added:
  mobilePhone String: OK
---> Index added:
  zipcode: zipcode.asc: OK
---> NO errors detected.(2) Warnings. Data being restored.
Delete Backed Data and Model? [y/N]:
---> Backup deleted
---> Modify complete. OK
```

[Go to Top](#mongoadmin)

### Drop Schema Model

Drops the named model after backing up the data and model.

```sh
# Model class name to be dropped
$ mongoadmin  --user adminemail.domain --password 12344%Aa --dropModel SpecialWidget
---> Data backed up.
---> Model backed up.
--->  Ok - Model dropped.
```

### Restore from Backup

Model and data are restored from backup. Command fails if the model was not backed up.

```sh
# Model class name to be dropped
$ mongoadmin  --user adminemail.domain --password 12344%Aa --restoreModel SpecialWidget
---> Data restored.
---> Model restored.
---> Ok - restore complete.
```

[Go to Top](#mongoadmin)

## Import data

You can import data from from other applications if that applicaton can export Data in JSON format. Google's Firestore exports data in a semi JSON format. *Mongoadmin* handles both formats. The file name
should be of ```<ModelName>.json```. *Mongoadmin* will treat the primary name as model name and extension is required to be `.json`.

### Supported formats

- **Google Firestore.** Primarily JSON format muliple lines per record. Record preceded by the record id.
- **JSON records.** One JSON object per record. Records separated by *newline*.
- **CSV Records**. First line in the file *must* be the header line, containing *comma separated* field names. The following lines contain comma separated values for the records.Each record separated by a *newline*. The number of fields and comma separated values must match else that record will not be imported.

If the model of the data being imported is not already registered you can specify `--register` flag, directing *mongoadmin* to register the model with the server and create primary index.

*Monggoadmin* presents the user with a list of fields derived from the JSON file. The user may choose one of these fields as the primary key for the collection, or press 'q' to skip a primary key for the collection. The following examples shows import of data that was exported from Google firestore.

```sh
mongoadmin --user adminemail.com --password 123456%aA --serverHome ../mongoserver --import customer.json --registerModel

--> Info - importing customer
.............
  [1] lastName
  [2] email
  [3] billingAddress
  [4] mobilePhone
  [5] firstName
   Enter a number to select or [q] for none
Choose:  2
 email selected.

Registering model: customer..
...done!


........................
$
```

Please note that the schema from the first logical data record is used to construct the Model Schema.
