var example = '''{
  "collectionName": "specialWidgets", // any unique name
  "primaryKey": "widgetname", // any unique field
  // field -> other collection
  "foreignKeys": { "product_id": "products", "supplier_id": "supplier" },
  // map of indexname: field.sortorder...
  "index": {"widgetProduct": "productId.asc", "wdigetSupplier": "supplierid"},
  // list of fields that are not updateable
  "noUpdate": ["widgetname", "product_id", "supplier_id"],
  // list of date fields in collection as path
  "dateFields": ["/lastUsed"],
  "fields": {
    "widgetName": "A widget name",
    "product_id": "addfdf12",
    "supplier_id": "adnfdfd",
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
}''';
