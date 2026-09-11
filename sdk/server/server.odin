package server

import jsonrpc "../jsonrpc"
import mcp "../mcp"
import transport_layer "../transport"
import "core:encoding/json"
import "core:fmt"
import "core:mem/virtual"

Server_Transport :: enum {
  stdio,
}

create_server :: proc(
  info: Server_Info,
  server_caps: mcp.Server_Capabilities,
  allocator := context.allocator,
) -> Server {
  return Server {
    info                                 = info,
    capabilities                         = server_caps,
    tools                                = make(Tools, allocator),
    resources                            = make(Resources, allocator),
    prompts                              = make(Prompts, allocator),

    // subscriptions
    subscriptions                        = make(Subscriptions, allocator),
    resources_templates                  = make(Resources_Templates, allocator),
    resources_list_changed_subscriptions = make(TRP_Subscriptions, allocator),
    tools_list_changed_subscriptions     = make(TRP_Subscriptions, allocator),
    prompts_list_changed_subscriptions   = make(TRP_Subscriptions, allocator),
    resources_subscriptions              = make(Resource_Subscriptions, allocator),
  }
}

// TODO:
destroy_server :: proc(s: ^Server) {
  unimplemented()
}

run :: proc(server: ^Server, srv_transport: Server_Transport, allocator := context.allocator) {
  transport, ok := make_transport(srv_transport, allocator)
  if !ok {
    return
  }
  defer transport.close(transport)

  run_with_transport(server, transport, allocator)
}

run_with_transport :: proc(
  server: ^Server,
  transport: ^transport_layer.Transport,
  allocator := context.allocator,
) {
  // use arena to allocate memory for the calls in the loop
  arena: virtual.Arena
  if err := virtual.arena_init_growing(&arena); err != nil {
    fmt.eprintfln("could not init arena: %v", err)
    return
  }
  defer virtual.arena_destroy(&arena)
  arena_allocator := virtual.arena_allocator(&arena)

  fmt.eprintln("Server running...")

  for {
    defer virtual.arena_free_all(&arena)
    context.allocator = arena_allocator

    bytes, err := transport.read(transport)
    if err != nil do break

    req, jsonrpc_err := jsonrpc.parse_request(bytes)
    if jsonrpc_err != nil {
      fmt.eprintfln("\n\ncould not parse req: %+v", jsonrpc_err)
      continue
    }

    fmt.eprintfln("CLIENT REQ:\n%+v", req)

    res := dispatch(server, req)
    if res == nil do continue


    res_bytes, marshal_err := json.marshal(res)
    if marshal_err != nil {
      fmt.eprintfln("\nRESPONSE:\n%+v", res)
      fmt.eprintfln("\nerror marshalling res: %+v", marshal_err)
      continue
    }

    transport_err := transport.write(transport, res_bytes)
    if transport_err != nil {
      fmt.eprintfln("\n\ncould not write to transport: %+v", transport_err)
      continue
    }

    fmt.eprintln("[OK] Sent response:\n")
    fmt.eprintfln("%+v", res)
  }
}

make_transport :: proc(
  srv_transport: Server_Transport,
  allocator := context.allocator,
) -> (
  ^transport_layer.Transport,
  bool,
) {
  transport: ^transport_layer.Transport
  switch srv_transport {
  case .stdio:
    stdio := transport_layer.stdio_create(allocator)
    transport = &stdio.transport
  case:
    fmt.eprintfln("transport not implemented: %v", srv_transport)
    return {}, false
  }

  return transport, true
}

