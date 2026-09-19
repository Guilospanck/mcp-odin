package jsonrpc_test

import jsonrpc "../../jsonrpc"
import "core:encoding/json"
import "core:testing"

@(test)
should_parse_params_correctly_when_array :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0", "method": "ping", "params": ["hello", true, 18, {"key_one": 1, "key_two": "help", "key_three": false}] }`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)


  testing.expect_value(t, err, nil)
  testing.expect(t, req.id == nil)
  testing.expect(t, req.jsonrpc == "2.0")
  testing.expect(t, req.method == "ping")

  params, params_is_json_array := req.params.(json.Array)
  testing.expect(t, params_is_json_array == true)
  testing.expect_value(t, len(params), 4)
  testing.expect_value(t, params[0].(json.String), "hello")
  testing.expect_value(t, params[1].(json.Boolean), true)
  testing.expect_value(t, params[2].(json.Integer), 18)

  params_fourth_pos, params_fourth_pos_is_object := params[3].(json.Object)
  testing.expect(t, params_fourth_pos_is_object == true)
  testing.expect(t, params_fourth_pos["key_one"].(json.Integer) == 1)
  testing.expect(t, params_fourth_pos["key_two"].(json.String) == "help")
  testing.expect(t, params_fourth_pos["key_three"].(json.Boolean) == false)
}

@(test)
should_parse_params_correctly_when_object :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0", "method": "ping", "params": {"larry": true, "john": "dude", "age": 18 } }`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)


  testing.expect_value(t, err, nil)
  testing.expect(t, req.id == nil)
  testing.expect(t, req.jsonrpc == "2.0")
  testing.expect(t, req.method == "ping")

  params, params_is_object := req.params.(json.Object)
  testing.expect(t, params_is_object == true)
  testing.expect(t, params["larry"].(json.Boolean) == true)
  testing.expect(t, params["john"].(json.String) == "dude")
  testing.expect(t, params["age"].(json.Integer) == 18)
}

@(test)
should_parse_even_when_missing_id :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0", "method": "ping", "params": {"larry": true } }`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  params, ok := req.params.(json.Object)

  testing.expect_value(t, err, nil)
  testing.expect(t, req.id == nil)
  testing.expect(t, req.jsonrpc == "2.0")
  testing.expect(t, req.method == "ping")
  testing.expect(t, ok == true && params["larry"].(json.Boolean) == true)
}

@(test)
should_parse_even_when_missing_params :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0", "method": "ping", id: "potato" }`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect_value(t, err, nil)
  testing.expect(t, req.params == nil)
  testing.expect(t, req.id == jsonrpc.ID("potato"))
  testing.expect(t, req.jsonrpc == "2.0")
  testing.expect(t, req.method == "ping")
}

@(test)
should_parse_when_id_is_null :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0", "method": "ping", "id": null}`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect_value(t, err, nil)
  testing.expect(t, req.id == nil)
  testing.expect(t, req.params == nil)
  testing.expect(t, req.jsonrpc == "2.0")
  testing.expect(t, req.method == "ping")
}

@(test)
should_error_when_jsonrpc_version_is_wrong :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "1.0", "method": "ping" }`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect(t, err != nil)
  testing.expect(t, err == jsonrpc.Request_Parse_Error.Unsupported_JSONRPC_Version)
}

@(test)
should_error_when_jsonrpc_version_is_missing :: proc(t: ^testing.T) {
  data := `{"method": "ping" }`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect(t, err != nil)
}

@(test)
should_error_when_missing_method :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0"}`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect(t, err != nil)
  testing.expect(t, err == jsonrpc.Request_Parse_Error.Missing_Method)
}

@(test)
should_error_when_method_starts_with_reserver_rpc_keyword :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0", "method": "rpc.ping" }`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect(t, err != nil)
  testing.expect(t, err == jsonrpc.Request_Parse_Error.Method_Not_Allowed)
}

@(test)
should_error_when_id_is_not_null_string_or_integer :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0", "method": "ping", "id": true}`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect(t, err != nil)

  unmarshal_error, is_unmarshal_error := err.(json.Unmarshal_Error)
  testing.expect_value(t, is_unmarshal_error, true)

  _, is_unsupported_type_error := unmarshal_error.(json.Unsupported_Type_Error)
  testing.expect_value(t, is_unsupported_type_error, true)
}

@(test)
should_error_when_jsonrpc_is_not_string :: proc(t: ^testing.T) {
  data := `{"jsonrpc": 2.0, "method": "ping"}`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect(t, err != nil)

  unmarshal_error, is_unmarshal_error := err.(json.Unmarshal_Error)
  testing.expect_value(t, is_unmarshal_error, true)

  _, is_unsupported_type_error := unmarshal_error.(json.Unsupported_Type_Error)
  testing.expect_value(t, is_unsupported_type_error, true)
}

@(test)
should_error_when_method_is_not_string :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0", "method": 18}`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect(t, err != nil)

  unmarshal_error, is_unmarshal_error := err.(json.Unmarshal_Error)
  testing.expect_value(t, is_unmarshal_error, true)

  _, is_unsupported_type_error := unmarshal_error.(json.Unsupported_Type_Error)
  testing.expect_value(t, is_unsupported_type_error, true)
}

@(test)
should_error_when_params_is_not_json_array_or_object :: proc(t: ^testing.T) {
  data := `{"jsonrpc": "2.0", "method": "ping", "params": "hey" }`

  allocator := context.temp_allocator
  defer free_all(allocator)

  req, err := jsonrpc.parse_request(transmute([]byte)data, allocator)

  testing.expect(t, err != nil)

  unmarshal_error, is_unmarshal_error := err.(json.Unmarshal_Error)
  testing.expect_value(t, is_unmarshal_error, true)

  _, is_unsupported_type_error := unmarshal_error.(json.Unsupported_Type_Error)
  testing.expect_value(t, is_unsupported_type_error, true)
}

