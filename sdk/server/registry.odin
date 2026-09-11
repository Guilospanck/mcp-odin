/*
  Storage. Hold the tables and the API that the SDK's users call at startup
  Registry never reads a request.
*/
package server

import jsonrpc "../jsonrpc"
import mcp "../mcp"
import "core:encoding/json"

// Re-export so users can use
Server_Info :: mcp.Server_Info
Server_Capabilities :: mcp.Server_Capabilities
Prompts_Capab :: mcp.Prompts_Capab
Resources_Capab :: mcp.Resources_Capab
Tools_Capab :: mcp.Tools_Capab

Tools_Call_Response :: mcp.Tools_Call_Response
Input_Schema_With_Properties :: mcp.Input_Schema_With_Properties
Text_Content :: mcp.Text_Content
Media_Content :: mcp.Media_Content
Content_Block :: mcp.Content_Block
No_Schema :: mcp.No_Schema
URI :: mcp.URI
Resources_Content :: mcp.Resources_Content
Blob_Resource_Contents :: mcp.Blob_Resource_Contents
Text_Resource_Contents :: mcp.Text_Resource_Contents

build_successfull_tools_call_response :: mcp.build_successfull_tools_call_response
build_failed_tools_call_response :: mcp.build_failed_tools_call_response
convert_schema_into_json_value :: mcp.convert_schema_into_json_value
encode_base64 :: mcp.encode_base64

Tool :: mcp.Tool
Resource :: mcp.Resource
Prompt :: mcp.Prompt

Error_Code :: mcp.Error_Code
decode_and_require :: mcp.decode_and_require

/**** TOOLS ****/
Tool_Handler :: #type proc(
  req: jsonrpc.JSONRPC_Request,
  args: json.Value,
) -> (
  mcp.Tools_Call_Response,
  mcp.Error_Code,
)

Tool_Name :: string
Tool_Entry :: struct {
  info:    mcp.Tool,
  handler: Tool_Handler,
}
Tools :: map[Tool_Name]Tool_Entry

/**** RESOURCES ****/
Resource_Handler :: #type proc(
  uri: mcp.URI,
  allocator := context.allocator,
) -> (
  []mcp.Resources_Content,
  mcp.Error_Code,
)
Resource_Entry :: struct {
  info:    mcp.Resource,
  handler: Resource_Handler,
}
Resources :: map[mcp.URI]Resource_Entry

Resources_Templates :: map[mcp.URI]mcp.Resource_Template

/**** PROMPTS ****/
Prompt_Name :: string

Prompt_Handler :: #type proc(
  args: json.Value,
  allocator := context.allocator,
) -> (
  []mcp.Prompt_Message,
  mcp.Error_Code,
)

Prompt_Entry :: struct {
  info:          mcp.Prompt,
  handler:       Prompt_Handler,
  required_args: []string,
}
Prompts :: map[Prompt_Name]Prompt_Entry

/**** SUBSCRIPTIONS ****/
Notification_Sink :: #type proc(data: []byte) -> mcp.Error_Code

Subscription_Id :: jsonrpc.Request_Id

Subscription :: struct {
  id:   Subscription_Id,
  // whether this subscription has already been acknowledged
  ack:  bool,
  // where to write the notification for this subscription
  sink: Notification_Sink,
}

Subscriptions :: map[Subscription_Id]Subscription
TRP_Subscriptions :: [dynamic]Subscription_Id
Resource_Subscriptions :: map[mcp.URI]Subscription_Id

/**** SERVER ****/
Server :: struct {
  info:                                 mcp.Server_Info,
  capabilities:                         mcp.Server_Capabilities,
  tools:                                Tools,
  resources:                            Resources,
  resources_templates:                  Resources_Templates,
  prompts:                              Prompts,

  // Subscriptions
  subscriptions:                        Subscriptions,
  resources_list_changed_subscriptions: TRP_Subscriptions,
  tools_list_changed_subscriptions:     TRP_Subscriptions,
  prompts_list_changed_subscriptions:   TRP_Subscriptions,
  resources_subscriptions:              Resource_Subscriptions,
}

JSONRPC_Notification :: struct {
  jsonrpc: string `json:"jsonrpc"`, // always "2.0"
  method:  string `json:"method"`, // e.g. "notifications/subscriptions/acknowledged"
  params:  json.Value `json:"params"`,
}

