module JsonParser

%default total

data JsonValue
  = JNull
  | JBool Bool
  | JNumber Double
  | JString String
  | JArray (List JsonValue)
  | JObject (List (String, JsonValue))

parseJson : String -> Either String JsonValue
parseJson _ = Left "E_SCHEMA_INVALID"
