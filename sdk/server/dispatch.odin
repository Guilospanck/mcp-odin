package server

import jsonrpc "../jsonrpc"
import mcp "../mcp"
import "base:intrinsics"
import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

/*
  Decision layer for the MCP server. It's a request-idn, response-out.
  Dispatch never stores anything (that's registry.odin responsibility)

  It handles things like:

  - id-presence rules (notification or just normal method)
  - lookups into registry
  - built-in methods
  - etc.
*/

// Called by the I/O loop at server.odin
dispatch :: proc(s: ^Server, req: jsonrpc.JSONRPC_Request, sink: Sink) -> Maybe(Response) {
  method, known := mcp.method_from_name(req.method)

  // We can only process methods that we know
  if !known {
    fmt.eprintfln("Method not recognised: %q", req.method)
    return nil
  }

  meta_err := validate_meta(req)
  if meta_err != nil {
    response_error := jsonrpc.Response_Error {
      code    = mcp.error_code_number(meta_err),
      message = mcp.error_code_message(meta_err),
    }
    return jsonrpc.create_error_response(
      error = response_error,
      id = jsonrpc.request_to_response_id(req.id),
    )
  }

  // TODO: check whether the request method requires a client capabilites. If the request doesn't have it,
  // then we return
  // missing required client capability for that method → -32021

  // Every request MUST have an ID. If not, we will handle it as a notification.
  if req.id == nil {
    return handle_notification(method, req, s)
  }

  return handle_request(method, req, s, sink)
}

validate_meta :: proc(req: jsonrpc.JSONRPC_Request) -> mcp.Error_Code {
  if req.params == nil {
    fmt.eprintln("request doesn't have .params")
    return mcp.Error_Code.Invalid_Params
  }

  obj: json.Object = nil

  params_array, is_array := req.params.(json.Array)
  if is_array {
    for param in params_array {
      params_object, is_object := param.(json.Object)
      if !is_object do continue

      // we found an object, check if it has the "_meta"
      meta, ok := params_object["_meta"]
      if !ok do continue

      // we found the _meta one
      obj = params_object
    }

  } else {
    params_object, is_object := req.params.(json.Object)
    if !is_object {
      fmt.eprintln("params nor array nor object")
      return mcp.Error_Code.Invalid_Params
    }

    obj = params_object
  }

  if obj == nil {
    fmt.eprintln("params nor array nor object or we didn't find _meta in there")
    return mcp.Error_Code.Invalid_Params
  }

  meta, ok := obj["_meta"]
  if !ok {
    fmt.eprintln("meta does not exist in params")
    return mcp.Error_Code.Invalid_Params
  }

  // at this point we do have at least an object keyed by "_meta".
  meta_obj, is_meta_object := meta.(json.Object)
  if !is_meta_object {
    fmt.eprintln("meta is not an object")
    return mcp.Error_Code.Invalid_Params
  }

  // now, check for and required fields
  // 1. protocol version
  pv, has_pv := meta_obj[mcp.meta_field_name(mcp.Meta_Field.Protocol_Version)]
  if !has_pv {
    fmt.eprintln("_meta missing required protocol version")
    return mcp.Error_Code.Invalid_Params
  }
  protocol_version, is_pv_string := pv.(json.String)
  if !is_pv_string {
    fmt.eprintln("_meta protocol version is not a string")
    return mcp.Error_Code.Invalid_Params
  }
  if !slice.contains(mcp.SUPPORTED_VERSIONS, protocol_version) {
    fmt.eprintln("unsupported protocol version")
    return mcp.Error_Code.Unsupported_Protocol_Version
  }

  // 2. client capabilities
  cc, has_cc := meta_obj[mcp.meta_field_name(mcp.Meta_Field.Client_Capabilities)]
  if !has_cc {
    fmt.eprintln("_meta missing required client capabilities")
    return mcp.Error_Code.Invalid_Params
  }

  bytes, _ := json.marshal(cc, {}, context.allocator)
  client_capabilities: mcp.Client_Capabilities
  err := json.unmarshal(bytes, &client_capabilities)
  if err != nil {
    fmt.eprintln("client capabilities in wrong format (not mcp.Client_Capabilities)")
    return mcp.Error_Code.Invalid_Params
  }

  return nil
}

Response :: union {
  jsonrpc.JSONRPC_Response,
  JSONRPC_Notification,
}

handle_request :: proc(
  method: mcp.Method,
  req: jsonrpc.JSONRPC_Request,
  s: ^Server,
  sink: Sink,
) -> Maybe(Response) {

  // TODO: remove #partial once we have all methods implemented
  #partial switch method {
  case mcp.Method.Server_Discover:
    return handle_req_response(req.id, server_discover(s))

  case mcp.Method.Tools_List:
    return handle_req_response(req.id, tools_list(s))

  case mcp.Method.Tools_Call:
    return handle_req_response(req.id, tools_call(s, req))

  case mcp.Method.Resources_List:
    return handle_req_response(req.id, resources_list(s))

  case mcp.Method.Resources_Read:
    return handle_req_response(req.id, resource_read(s, req))

  case mcp.Method.Resources_Templates_List:
    return handle_req_response(req.id, resources_templates_list(s, req))

  case mcp.Method.Prompts_List:
    return handle_req_response(req.id, prompts_list(s, req))

  case mcp.Method.Prompts_Get:
    return handle_req_response(req.id, prompt_read(s, req))

  case mcp.Method.Subscriptions_Listen:
    notification_method, notification_params, err := subscriptions_listen(s, req, sink)

    if err != nil {
      response_error := jsonrpc.Response_Error {
        code    = mcp.error_code_number(err),
        message = mcp.error_code_message(err),
      }
      return jsonrpc.create_error_response(
        error = response_error,
        id = jsonrpc.request_to_response_id(req.id),
      )
    }
    // TODO: we have to update the ack of subscriptions

    return build_notification(method = notification_method, params = notification_params)

  case:
    fmt.eprintfln("known method not implemented yet: %+v", method)
    return nil
  }
}

/*

  Notice that *ONLY* 'notifications/progress'  and 'notifications/cancelled'
  are both ways (client <-> server), so they are the ONLY ones that we could handle
  on a request in a MCP server.

*/
handle_notification :: proc(
  method: mcp.Method,
  req: jsonrpc.JSONRPC_Request,
  s: ^Server,
) -> Maybe(Response) {
  #partial switch method {
  case mcp.Method.Notifications_Progress:
    fmt.eprintln("Need to implement 'notifications/progress'")
    return nil
  case mcp.Method.Notifications_Cancelled:
    fmt.eprintln("Need to implement 'notifications/cancelled'")
    return nil
  case:
    fmt.eprintfln("notification not known or malformed: %+v", method)
    return nil
  }
}

// Walk through the tools list in the server's registry
tools_list :: proc(s: ^Server) -> (mcp.Tools_List_Response, mcp.Error_Code) {
  tools := make([]mcp.Tool, len(s.tools), context.allocator)

  i := 0
  for _, entry in s.tools {
    tools[i] = entry.info
    i += 1
  }

  // The spec wants this to be ordered
  slice.sort_by(tools, proc(a, b: mcp.Tool) -> bool {return a.name < b.name})

  return mcp.Tools_List_Response {
      result_type = mcp.result_type_name(mcp.Result_Type.Complete),
      tools       = tools,
      // 3 days
      ttl_ms      = 60 * 60 * 24 * 3 * 1000,
      cache_scope = mcp.cache_scope_name(mcp.Cache_Scope.Public),
    }, nil
}

check_tools_call_input_valid :: proc(
  tools_call_req: mcp.Tools_Call_Request,
  tool_entry: Tool_Entry,
) -> Maybe(mcp.Error_Code) {
  input_schema := tool_entry.info.input_schema

  // If input states that it requires no parameters, then there's no input
  // to be validated
  _, is_explicit_no_param := input_schema.(mcp.Input_Schema_Explicit_Empty_Object)
  if is_explicit_no_param do return nil
  _, is_no_param := input_schema.(mcp.Input_Schema_Empty_Object)
  if is_no_param do return nil

  input_args := tools_call_req.arguments

  input_schema_with_properties, is_input_with_properties := input_schema.(mcp.Input_Schema_With_Properties)
  if !is_input_with_properties do return mcp.Error_Code.Invalid_Params

  // validate required fields
  is_required_ok := mcp.check_required(
    args = input_args,
    required = input_schema_with_properties.required[:],
  )
  if !is_required_ok do return mcp.Error_Code.Invalid_Params

  return nil
}

tools_call :: proc(
  s: ^Server,
  req: jsonrpc.JSONRPC_Request,
) -> (
  mcp.Tools_Call_Response,
  mcp.Error_Code,
) {
  // if the server doesn't allow tool calling, then return
  if s.capabilities.tools == nil {
    return {}, mcp.Error_Code.Method_Not_Found
  }

  // first validate that at least the shape of params is correct for a tools/call request.
  tools_call_req, tools_call_error := mcp.tools_call_validate(
    jsonrpc_request_params_to_json_value(req.params),
  )
  if tools_call_error != nil {
    return {}, tools_call_error
  }

  tool_name := tools_call_req.name

  // we can only call tools that the server has
  tool_entry, has_tool := s.tools[tool_name]
  if !has_tool {
    return {}, mcp.Error_Code.Invalid_Params
  }

  input_err := check_tools_call_input_valid(tools_call_req, tool_entry)
  if input_err != nil {
    return {}, mcp.Error_Code.Invalid_Params
  }

  // call the tool
  tools_call_res, tools_call_res_error := tool_entry.handler(req, tools_call_req.arguments)
  if tools_call_res_error != nil {
    return {}, tools_call_res_error
  }

  // validate that, should the tool have an outputSchema defined,
  // it also has the structuredContent in the response
  output_schema := tool_entry.info.output_schema
  if output_schema != nil && tools_call_res.structured_content == nil {
    fmt.eprintln("output schema was defined but no structuredContent in tools/call response")
    return {}, mcp.Error_Code.Invalid_Params
  }

  return tools_call_res, nil
}

add_tool :: proc(
  s: ^Server,
  info: mcp.Tool,
  handler: Tool_Handler,
) -> Maybe(jsonrpc.Response_Error) {
  _, tool_already_exists := s.tools[info.name]
  if tool_already_exists {
    return jsonrpc.Response_Error {
      code = i64(mcp.Error_Code.Invalid_Request),
      message = mcp.error_code_message(Error_Code.Invalid_Params),
      data = "Tool already exists",
    }
  }

  // set the server capabilities if unset
  if s.capabilities.tools == nil {
    s.capabilities.tools = mcp.Tools_Capab{}
  }

  s.tools[info.name] = {
    info    = info,
    handler = handler,
  }

  fmt.eprintfln("Saved %q tool", info.name)

  maybe_send_notification(s, Subscription_Type.Tool, info.name)
  return nil
}

// Walk through the resources list in the server's registry
resources_list :: proc(s: ^Server) -> (mcp.Resources_List_Response, mcp.Error_Code) {
  srv_resources := s.resources

  resources := make([]mcp.Resource, len(srv_resources))

  i := 0
  for _, res in srv_resources {
    resources[i] = res.info
    i += 1
  }

  return mcp.Resources_List_Response {
      result_type = mcp.result_type_name(mcp.Result_Type.Complete),
      resources   = resources,
      // 3 days
      ttl_ms      = 60 * 60 * 24 * 3 * 1000,
      cache_scope = mcp.cache_scope_name(mcp.Cache_Scope.Public),
    }, nil
}

add_resource :: proc(
  s: ^Server,
  info: mcp.Resource,
  handler: Resource_Handler,
) -> Maybe(jsonrpc.Response_Error) {
  _, resource_already_exists := s.resources[info.uri]
  if resource_already_exists do return nil

  resources_capab := s.capabilities.resources
  if resources_capab == nil {
    s.capabilities.resources = mcp.Resources_Capab{}
  }

  s.resources[info.uri] = Resource_Entry {
    info    = info,
    handler = handler,
  }

  fmt.eprintfln("Saved %q resource", info.uri)

  maybe_send_notification(s, Subscription_Type.Resources, info.uri)

  return nil
}

update_resource :: proc(
  s: ^Server,
  info: mcp.Resource,
  handler: Resource_Handler,
) -> Maybe(jsonrpc.Response_Error) {
  _, resource_already_exists := s.resources[info.uri]
  if !resource_already_exists {
    return jsonrpc.Response_Error {
      code = i64(mcp.Error_Code.Invalid_Request),
      message = mcp.error_code_message(Error_Code.Invalid_Params),
      data = "Resource does not exist",
    }
  }

  s.resources[info.uri] = Resource_Entry {
    info    = info,
    handler = handler,
  }

  fmt.eprintfln("Updated %q resource", info.uri)

  maybe_send_notification(s, Subscription_Type.Resource, info.uri)

  return nil
}

resources_templates_list :: proc(
  s: ^Server,
  req: jsonrpc.JSONRPC_Request,
) -> (
  mcp.Resources_Templates_List_Response,
  mcp.Error_Code,
) {

  // TODO: use params to check for next_cursor
  _, err := mcp.decode_into_type(
    jsonrpc_request_params_to_json_value(req.params),
    mcp.Resources_Templates_List_Request,
  )
  if err != nil do return {}, err

  srv_resources_templates := s.resources_templates

  resources := make([]mcp.Resource_Template, len(srv_resources_templates))

  i := 0
  for _, res in srv_resources_templates {
    resources[i] = res
    i += 1
  }

  return mcp.Resources_Templates_List_Response {
      result_type        = mcp.result_type_name(mcp.Result_Type.Complete),
      resource_templates = resources,
      // 3 days
      ttl_ms             = 60 * 60 * 24 * 3 * 1000,
      cache_scope        = mcp.cache_scope_name(mcp.Cache_Scope.Public),
    }, nil
}

add_resource_template :: proc(
  s: ^Server,
  info: mcp.Resource_Template,
) -> Maybe(jsonrpc.Response_Error) {
  _, resource_already_exists := s.resources_templates[info.uri_template]
  if resource_already_exists do return nil

  resources_capab := s.capabilities.resources
  if resources_capab == nil {
    s.capabilities.resources = mcp.Resources_Capab{}
  }

  s.resources_templates[info.uri_template] = info
  fmt.eprintfln("Saved %q resource template", info.uri_template)
  return nil
}

resource_read :: proc(
  s: ^Server,
  req: jsonrpc.JSONRPC_Request,
) -> (
  mcp.Resources_Read_Response,
  mcp.Error_Code,
) {
  params, params_error := mcp.decode_into_type(
    jsonrpc_request_params_to_json_value(req.params),
    mcp.Resources_Read_Request,
  )
  if params_error != nil {
    return {}, params_error
  }

  uri := params.uri

  resource, exists := s.resources[uri]
  if !exists {
    return {}, mcp.Error_Code.Invalid_Params
  }

  contents, error := resource.handler(uri)
  if error != nil {
    return {}, mcp.Error_Code.Internal_Error
  }

  return mcp.Resources_Read_Response {
      result_type = mcp.result_type_name(mcp.Result_Type.Complete),
      contents    = contents,
      // 3 days
      ttl_ms      = 60 * 60 * 24 * 3 * 1000,
      cache_scope = mcp.cache_scope_name(mcp.Cache_Scope.Public),
    }, nil
}

Subscription_Type :: enum {
  Prompt,
  Resources,
  Resource,
  Tool,
}

@(private = "file")
maybe_send_notification :: proc(s: ^Server, subs_type: Subscription_Type, identifier: string) {
  // TODO: should not send notification
  // if subscription hasn;t been acknowledged yet
  switch subs_type {
  case .Prompt:
  case .Resources:
  case .Resource:
    resources_capab, has_resources_capab := s.capabilities.resources.(mcp.Resources_Capab)
    should_notify := has_resources_capab && (resources_capab.subscribe.? or_else false)
    if !should_notify do return

    if subs_id, ok := s.resources_subscriptions[identifier]; ok {
      if subscription, ok := s.subscriptions[subs_id]; ok {
        // TODO:  send actual notification
        subscription.sink.write(subscription.sink.data, transmute([]u8)identifier)
      }
    }


  case .Tool:
    tools_capab, has_tools_capab := s.capabilities.tools.(mcp.Tools_Capab)
    should_notify := has_tools_capab && (tools_capab.list_changed.? or_else false)
    if !should_notify do return

    for subs_id in s.tools_list_changed_subscriptions {
      if subscription, ok := s.subscriptions[subs_id]; ok {
        // TODO:  send actual notification
        subscription.sink.write(subscription.sink.data, transmute([]u8)identifier)
      }
    }

  case:
    fmt.eprintfln("Subscription type %v not implemented on check", subs_type)
  }
}

add_prompt :: proc(
  s: ^Server,
  prompt: mcp.Prompt,
  handler: Prompt_Handler,
  required_args: []string,
) -> Maybe(mcp.Error_Code) {
  _, prompt_exist := s.prompts[prompt.name]
  if prompt_exist do return nil

  if s.capabilities.prompts == nil {
    s.capabilities.prompts = mcp.Prompts_Capab{}
  }

  s.prompts[prompt.name] = Prompt_Entry {
    info          = prompt,
    handler       = handler,
    required_args = required_args,
  }

  fmt.eprintfln("Saved %q prompt", prompt.name)

  maybe_send_notification(s, Subscription_Type.Prompt, prompt.name)

  return nil
}

prompts_list :: proc(
  s: ^Server,
  req: jsonrpc.JSONRPC_Request,
) -> (
  mcp.Prompts_List_Response,
  mcp.Error_Code,
) {
  // TODO: do something if "cursor"
  _, params_error := mcp.decode_into_type(
    jsonrpc_request_params_to_json_value(req.params),
    mcp.Resources_Read_Request,
  )
  if params_error != nil {
    return {}, params_error
  }

  srv_prompts := s.prompts

  prompts := make([]mcp.Prompt, len(srv_prompts))

  i := 0
  for _, res in srv_prompts {
    prompts[i] = res.info
    i += 1
  }

  return mcp.Prompts_List_Response {
      result_type = mcp.result_type_name(mcp.Result_Type.Complete),
      prompts     = prompts,
      // 3 days
      ttl_ms      = 60 * 60 * 24 * 3 * 1000,
      cache_scope = mcp.cache_scope_name(mcp.Cache_Scope.Public),
    }, nil
}

prompt_read :: proc(
  s: ^Server,
  req: jsonrpc.JSONRPC_Request,
) -> (
  mcp.Prompt_Get_Result,
  mcp.Error_Code,
) {
  params, params_error := mcp.decode_into_type(
    jsonrpc_request_params_to_json_value(req.params),
    mcp.Prompt_Get_Request,
  )
  if params_error != nil {
    return {}, params_error
  }

  name := params.name
  args := params.arguments

  prompt, exists := s.prompts[name]
  if !exists {
    return {}, mcp.Error_Code.Invalid_Params
  }

  // validate args given the `required` info
  required := prompt.required_args
  if len(required) > 0 && args == nil {
    return {}, mcp.Error_Code.Invalid_Params
  }

  _, args_value, convert_args_err := convert_schema_into_json_value(args)
  if convert_args_err != nil {
    return {}, mcp.Error_Code.Invalid_Params
  }

  if !mcp.check_required(args_value, required) {
    return {}, mcp.Error_Code.Invalid_Params
  }

  prompt_messages, error := prompt.handler(args_value)
  if error != nil {
    return {}, mcp.Error_Code.Internal_Error
  }

  return mcp.Prompt_Get_Result {
      result_type = mcp.result_type_name(mcp.Result_Type.Complete),
      messages = prompt_messages,
      description = prompt.info.description,
    },
    nil
}

@(private = "file")
decide_which_subscription_listen_to_accept :: proc(
  s: ^Server,
  subscription: Subscription,
  filters: mcp.Subscription_Filter,
) -> (
  mcp.Subscription_Filter,
  mcp.Error_Code,
) {
  subscription_id := subscription.id

  server_allows_any_subscription := false
  notification_filters := mcp.Subscription_Filter{}

  // tools list changed caps
  if v, ok := filters.tools_list_changed.?; ok && v {
    tools_capab, has_tools_capab := s.capabilities.tools.(mcp.Tools_Capab)

    if has_tools_capab && (tools_capab.list_changed.? or_else false) {
      server_allows_any_subscription = true
      append(&s.tools_list_changed_subscriptions, subscription_id)

      notification_filters.tools_list_changed = true
    }
  }

  // prompts list changed caps
  if v, ok := filters.prompts_list_changed.?; ok && v {
    prompts_capab, has_prompts_capab := s.capabilities.prompts.(mcp.Prompts_Capab)

    if has_prompts_capab && (prompts_capab.list_changed.? or_else false) {
      server_allows_any_subscription = true
      append(&s.prompts_list_changed_subscriptions, subscription_id)

      notification_filters.prompts_list_changed = true
    }
  }

  resources_capab, has_resources_capab := s.capabilities.resources.(mcp.Resources_Capab)

  // resources list changed caps
  if v, ok := filters.resources_list_changed.?; ok && v {
    if has_resources_capab && (resources_capab.list_changed.? or_else false) {
      server_allows_any_subscription = true
      append(&s.resources_list_changed_subscriptions, subscription_id)

      notification_filters.resources_list_changed = true
    }
  }

  // resources subscribe caps
  if v, ok := filters.resource_subscriptions.?; ok && len(v) > 0 {
    if has_resources_capab && (resources_capab.subscribe.? or_else false) {
      server_allows_any_subscription = true
      subs := make([]string, len(v), context.allocator)

      i := 0
      for uri in v {
        key := strings.clone(uri, registry_allocator(s))
        s.resources_subscriptions[key] = subscription_id
        subs[i] = key
        i += 1
      }

      notification_filters.resource_subscriptions = subs
    }
  }

  if !server_allows_any_subscription do return {}, mcp.Error_Code.Method_Not_Found

  s.subscriptions[subscription_id] = subscription

  return notification_filters, nil
}

subscriptions_listen :: proc(
  s: ^Server,
  req: jsonrpc.JSONRPC_Request,
  sink: Sink,
) -> (
  notification_method: mcp.Method,
  notification_params: mcp.Subscriptions_Acknowledged_Notification_Params,
  notification_error: mcp.Error_Code,
) {
  params, params_error := mcp.decode_into_type(
    jsonrpc_request_params_to_json_value(req.params),
    mcp.Subscriptions_Listen_Request,
  )
  if params_error != nil {
    return {}, {}, params_error
  }

  subscription_id := req.id
  filters := params.notifications

  // Decide which - if any - subscriptions this server is able
  // to acknowledge
  notification_filters, err_capabilities := decide_which_subscription_listen_to_accept(
    s,
    Subscription{id = subscription_id, ack = false, sink = sink},
    filters,
  )
  if err_capabilities != nil do return {}, {}, err_capabilities

  meta := make(mcp.Meta, context.allocator)
  meta[mcp.meta_field_name(mcp.Meta_Field.Subscription_Id)] = jsonrpc.request_id_to_json_value(
    subscription_id,
  )
  subs_notif_params := mcp.Subscriptions_Acknowledged_Notification_Params {
    meta          = meta,
    notifications = notification_filters,
  }

  // send acknowledgement of the filters that we're gonna accept
  return mcp.Method.Notifications_Subscriptions_Acknowledged, subs_notif_params, nil
}


server_discover :: proc(s: ^Server) -> (mcp.Server_Discover_Response, mcp.Error_Code) {
  return mcp.Server_Discover_Response {
      result_type = mcp.result_type_name(mcp.Result_Type.Complete),
      supported_versions = mcp.SUPPORTED_VERSIONS,
      capabilities = s.capabilities,
      meta = mcp.Server_Discover_Response_Meta{server_info = s.info},
      // 3 days
      ttl_ms = 60 * 60 * 24 * 3 * 1000,
      cache_scope = mcp.cache_scope_name(mcp.Cache_Scope.Public),
    }, nil
}

jsonrpc_request_params_to_json_value :: proc(p: jsonrpc.Request_Params) -> json.Value {
  switch v in p {
  case json.Object:
    return v
  case json.Array:
    return v
  case:
    return nil
  }
}

make_tools_handler :: proc(
  $I: typeid, // input compile-time type
  $O: typeid, // output compile-time type
  $inner: proc(
    req: jsonrpc.JSONRPC_Request,
    input: I,
  ) -> (
    mcp.Tools_Call_Response,
    mcp.Error_Code,
  ),
) -> Tool_Handler where intrinsics.type_is_struct(I) {

  fn :: proc(
    req: jsonrpc.JSONRPC_Request,
    input: json.Value,
  ) -> (
    mcp.Tools_Call_Response,
    mcp.Error_Code,
  ) {
    // validate input
    v, err := mcp.decode_into_type(input, I)
    if err != nil {
      return {}, mcp.Error_Code.Invalid_Params
    }

    tool_res, tool_err := inner(req, v)
    if tool_err != nil || O == mcp.No_Schema do return tool_res, tool_err

    // From here onwards: output schema is defined
    structured_content := tool_res.structured_content
    // in that case, structured_content becomes REQUIRED
    if structured_content == nil do return {}, mcp.Error_Code.Invalid_Params

    sc := structured_content.(json.Value)

    // validates that it follows the correct output schema
    _, output_decode_err := mcp.decode_into_type(sc, O)
    if output_decode_err != nil {
      return {}, mcp.Error_Code.Invalid_Params
    }

    return tool_res, tool_err
  }

  return fn
}

make_prompts_handler :: proc(
  $T: typeid,
  $inner: proc(args: T, allocator := context.allocator) -> ([]mcp.Prompt_Message, mcp.Error_Code),
) -> Prompt_Handler {
  fn :: proc(
    args: json.Value,
    allocator := context.allocator,
  ) -> (
    []mcp.Prompt_Message,
    mcp.Error_Code,
  ) {
    args_t, error := mcp.decode_into_type(args, T)
    if error != nil do return {}, error

    return inner(args_t, allocator)
  }

  return fn
}

handle_req_response :: proc(
  req_id: jsonrpc.Request_Id,
  data: any,
  err: mcp.Error_Code,
) -> jsonrpc.JSONRPC_Response {
  if err != nil {
    response_error := jsonrpc.Response_Error {
      code    = mcp.error_code_number(err),
      message = mcp.error_code_message(err),
    }
    return jsonrpc.create_error_response(
      error = response_error,
      id = jsonrpc.request_to_response_id(req_id),
    )
  }

  return jsonrpc.create_result_response(data = data, id = jsonrpc.request_to_response_id(req_id))
}

build_notification :: proc(method: mcp.Method, params: $P) -> JSONRPC_Notification {
  _, pv, _ := mcp.convert_schema_into_json_value(params)

  return JSONRPC_Notification {
    jsonrpc = jsonrpc.JSONRPC_VERSION,
    method = mcp.method_name(method),
    params = pv,
  }
}

