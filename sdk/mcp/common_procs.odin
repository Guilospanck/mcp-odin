package mcp

import "core:encoding/base64"
import "core:encoding/json"
import "core:os"

convert_schema_into_json_value :: proc(schema: any) -> ([]byte, json.Value, Error_Code) {
  schema_bytes, schema_marshal_err := json.marshal(schema)
  if schema_marshal_err != nil {
    return {}, {}, Error_Code.Invalid_Params
  }

  json_value_schema: json.Value
  schema_structured_err := json.unmarshal(schema_bytes, &json_value_schema)
  if schema_structured_err != nil {
    return {}, {}, Error_Code.Invalid_Params
  }

  return schema_bytes, json_value_schema, nil
}

// Decode a json.Value into a type T and validate that the
// `require`d fields are present
//
decode_and_require :: proc(args: json.Value, $T: typeid, required: []string) -> (T, Error_Code) {
  is_required_ok := check_required(args, required)
  if !is_required_ok {
    return {}, Error_Code.Invalid_Params
  }

  return decode_into_type(args, T)
}

// INFO:
// typeid here needs to be $ (compile time) because of res: T
decode_into_type :: proc(args: json.Value, $T: typeid) -> (T, Error_Code) {
  bytes, _ := json.marshal(args)

  res: T
  err := json.unmarshal(bytes, &res)
  if err != nil {
    return {}, Error_Code.Invalid_Params
  }

  return res, nil
}

check_required :: proc(args: json.Value, required: []string) -> bool {
  args_as_obj, is_args_obj := args.(json.Object)
  if !is_args_obj {
    return false
  }

  for req in required {
    _, exists := args_as_obj[req]
    if !exists {
      return false
    }
  }

  return true
}

encode_base64 :: proc(file_path: string, allocator := context.allocator) -> string {
  bytes, _ := os.read_entire_file(file_path, allocator)
  data, _ := base64.encode(bytes, allocator = allocator)
  return data
}
