package hello_mcp_server

import mcp_sdk "../../../sdk/server"
import prompts "./prompts"
import resources "./resources"
import tools "./tools"
import "core:fmt"

main :: proc() {
  server := mcp_sdk.create_server(
    info = mcp_sdk.Server_Info {
      name = "hello-odin-mcp-server",
      title = "Hello MCP Server",
      version = "1.0.0",
    },
    server_caps = mcp_sdk.Server_Capabilities {
      prompts = mcp_sdk.Prompts_Capab{list_changed = true},
      resources = mcp_sdk.Resources_Capab{list_changed = true, subscribe = true},
      tools = mcp_sdk.Tools_Capab{list_changed = true},
    },
  )
  defer mcp_sdk.destroy_server(server)

  {
    context.allocator = mcp_sdk.registry_allocator(server)

    // tools
    hello_tool_err := mcp_sdk.add_tool(
      s = server,
      info = tools.get_hello_tool_info(),
      handler = mcp_sdk.make_tools_handler(
        tools.Hello_Tool_Input,
        tools.Hello_Tool_Output,
        tools.hello_tool,
      ),
    )
    if hello_tool_err != nil {
      fmt.eprintfln("%+v", hello_tool_err)
      return
    }

    // resources
    resource_info := resources.get_hello_resource()
    hello_resource_err := mcp_sdk.add_resource(
      s = server,
      info = resource_info,
      handler = resources.hello_resource_handler,
    )
    if hello_resource_err != nil {
      fmt.eprintfln("%+v", hello_resource_err)
      return
    }
    // update resource
    new_resource_info := resource_info
    new_resource_info.title = "new_title_hello_resource"
    hello_resource_updated_err := mcp_sdk.update_resource(
      s = server,
      info = new_resource_info,
      handler = resources.hello_resource_handler,
    )
    if hello_resource_updated_err != nil {
      fmt.eprintfln("%+v", hello_resource_updated_err)
      return
    }

    // prompts
    hello_prompt_info := prompts.get_hello_prompt()
    hello_prompt_handler := mcp_sdk.make_prompts_handler(
      T = prompts.Hello_Prompt_Args,
      inner = prompts.hello_prompt_handler,
    )
    hello_prompt_err := mcp_sdk.add_prompt(
      s = server,
      prompt = hello_prompt_info,
      handler = hello_prompt_handler,
      required_args = {"name"},
    )
    if hello_prompt_err != nil {
      fmt.eprintfln("%+v", hello_prompt_err)
      return
    }
  }

  mcp_sdk.run(server, .stdio)
}

