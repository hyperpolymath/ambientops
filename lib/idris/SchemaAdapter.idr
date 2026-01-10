module SchemaAdapter

%default total

import JsonParser

record Schema where
  constructor MkSchema
  schemaId : String

validateSchema : Schema -> JsonValue -> Either String ()
validateSchema _ _ = Right ()
