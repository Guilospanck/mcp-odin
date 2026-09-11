package jsonrpc

import "core:encoding/json"

/*

  JSON-RPC allows you to perform RPC (Remote Procedure Call) via a JSON.

  It tells you "represent that function call as a JSON"

*/

JSONRPC_VERSION :: "2.0"

ID :: union {
  string,
  i64,
}

request_to_response_id :: proc(rid: Request_Id) -> Response_Id {
  switch id in rid {
  case ID:
    return id // string or i64 — pass through
  case json.Null:
    return nil // shouldn't reach a response
  }
  return nil
}

request_id_to_json_value :: proc(rid: Request_Id) -> json.Value {

  switch id in rid {
  case ID:
    switch i in id {
    case string:
      return json.String(i)
    case i64:
      return json.Integer(i)
    }

  case json.Null:
    return nil
  }

  return nil
}

