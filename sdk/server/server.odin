package server

import jsonrpc "../jsonrpc"
import mcp "../mcp"
import transport_layer "../transport"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"

Server_Transport :: enum {
  stdio,
}

create_server :: proc(
  info: Server_Info,
  server_caps: mcp.Server_Capabilities,
  allocator := context.allocator,
) -> ^Server {
  s := new(Server, allocator)
  s.info = info
  s.capabilities = server_caps
  s.allocator = allocator

  if err := virtual.arena_init_growing(&s.registry_arena); err != nil {
    panic("could not instantiate arena")
  }

  a_alloc := virtual.arena_allocator(&s.registry_arena)

  s.tools = make(Tools, a_alloc)
  s.resources = make(Resources, a_alloc)
  s.prompts = make(Prompts, a_alloc)

  // subscriptions
  s.subscriptions = make(Subscriptions, a_alloc)
  s.resources_templates = make(Resources_Templates, a_alloc)
  s.resources_list_changed_subscriptions = make(TRP_Subscriptions, a_alloc)
  s.tools_list_changed_subscriptions = make(TRP_Subscriptions, a_alloc)
  s.prompts_list_changed_subscriptions = make(TRP_Subscriptions, a_alloc)
  s.resources_subscriptions = make(Resource_Subscriptions, a_alloc)

  return s
}

registry_allocator :: proc(s: ^Server) -> mem.Allocator {
  return virtual.arena_allocator(&s.registry_arena)
}

destroy_server :: proc(s: ^Server) {
  virtual.arena_destroy(&s.registry_arena)
  free(s, s.allocator)
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
    should_print_full_res := len(res_bytes) < 2048

    if marshal_err != nil {
      if should_print_full_res {
        fmt.eprintfln("\nRESPONSE:\n%+v", res)
      } else {
        fmt.eprintfln("\nRESPONSE (size): %d bytes", len(res_bytes))
      }
      fmt.eprintfln("\nerror marshalling res: %+v", marshal_err)
      continue
    }

    transport_err := transport.write(transport, res_bytes)
    if transport_err != nil {
      fmt.eprintfln("\n\ncould not write to transport: %+v", transport_err)
      continue
    }

    fmt.eprintln("[OK] Sent response:\n")
    if should_print_full_res {
      fmt.eprintfln("%+v", res)
    } else {
      fmt.eprintfln("\nSize: %d bytes", len(res_bytes))
    }
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

