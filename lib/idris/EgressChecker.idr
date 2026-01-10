module EgressChecker

%default total

data Decision = Allow String | Deny String

import JsonParser
import SchemaAdapter

record Policy where
  constructor MkPolicy
  maxPayloadBytes : Int

checkEgress : Policy -> Schema -> String -> Decision
checkEgress policy schema payload =
  if length payload > policy.maxPayloadBytes then
    Deny "E_SIZE_EXCEEDED"
  else
    case parseJson payload of
      Left err => Deny err
      Right json =>
        case validateSchema schema json of
          Left err => Deny err
          Right () => Allow payload
