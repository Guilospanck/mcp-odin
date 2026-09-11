package mcp

import "core:encoding/json"
/*

1. Requests

=> Unline JSON-RPC, the id of a request MUST NOT be null.
=> The request id MUST NOT have been previously used by the requestor within the same session

2. Responses

=> the id, when an error, MAY be optional in the cases of a parse error, for example.

3. Notifications

=> Are sent from client to server (or vice versa) as a one-way message (MUST NOT send a response)
=> MUST NOT include an ID

4. JSON schemas

=> Client and servers MUST support JSON Schema 2020-12 as default dialect
=> They also MUST validate schemas according to their declared (or default) dialect.
When they do not support a dialect, they MUST handle it gracefully, with an error indicating
that (instead of just breaking the application)
=> They SHOULD document which dialects they support.

*/

PROTOCOL_VERSION :: "2026-07-28"
SUPPORTED_VERSIONS := []string{PROTOCOL_VERSION}

Error_Code :: enum i64 {
  // JSON-RPC standard
  Parse_Error,
  Invalid_Request,
  Method_Not_Found,
  Invalid_Params,
  Internal_Error,

  // MCP-specific (2026-07-28)
  Header_Mismatch,
  Missing_Required_Client_Capability,
  Unsupported_Protocol_Version,
}

error_code_number :: proc(e: Error_Code) -> i64 {
  switch e {
  case .Parse_Error:
    return -32700
  case .Invalid_Request:
    return -32600
  case .Method_Not_Found:
    return -32601
  case .Invalid_Params:
    return -32602
  case .Internal_Error:
    return -32603
  case .Header_Mismatch:
    return -32020
  case .Missing_Required_Client_Capability:
    return -32021
  case .Unsupported_Protocol_Version:
    return -32022
  }
  return -32603 // fallback: internal
}

error_code_message :: proc(e: Error_Code) -> string {
  switch e {
  case .Parse_Error:
    return "Parse error"
  case .Invalid_Request:
    return "Invalid Request"
  case .Method_Not_Found:
    return "Method not found"
  case .Invalid_Params:
    return "Invalid params"
  case .Internal_Error:
    return "Internal error"
  case .Header_Mismatch:
    return "Header mismatch"
  case .Missing_Required_Client_Capability:
    return "Missing required client capability"
  case .Unsupported_Protocol_Version:
    return "Unsupported protocol version"
  }
  return "Internal error"
}

error_code_from_number :: proc(n: i64) -> (Error_Code, bool) {
  switch n {
  case -32700:
    return .Parse_Error, true
  case -32600:
    return .Invalid_Request, true
  case -32601:
    return .Method_Not_Found, true
  case -32602:
    return .Invalid_Params, true
  case -32603:
    return .Internal_Error, true
  case -32020:
    return .Header_Mismatch, true
  case -32021:
    return .Missing_Required_Client_Capability, true
  case -32022:
    return .Unsupported_Protocol_Version, true
  }
  // -32000..-32099 is the server-error band — not a named code
  if n >= -32099 && n <= -32000 do return .Internal_Error, true
  return {}, false
}

Method :: enum {
  /****** Client -> Server (request) ******/

  // Discover server identity & capabilities
  Server_Discover,
  // List available tools
  Tools_List,
  // Execute a tool
  Tools_Call,
  // List resources
  Resources_List,
  // List resource templates
  Resources_Templates_List,
  // Read a resource
  Resources_Read,
  // Subscribe to resource change streams
  Subscriptions_Listen,
  // List prompts
  Prompts_List,
  // Get a prompt
  Prompts_Get,
  // Argument completion
  Completion_Complete,

  /****** Server -> Client (request) ******/

  // Request user input (MRTR pattern)
  Elicitation_Create,

  /****** Notifications (one-way, no response) ******/

  // Server announces tool list changed
  Notifications_Tools_List_Changed,
  // Server announces resource list changed
  Notifications_Resources_List_Changed,
  // Server announces resource content updated
  Notifications_Resources_Updated,
  // Server announces prompt list changed
  Notifications_Prompts_List_Changed,
  // Server acknowledges a subscription
  Notifications_Subscriptions_Acknowledged,
  // Progress reporting for long-running operations
  Notifications_Progress,
  // Cancel a previously issued request
  Notifications_Cancelled,
  // Log message from a server or client
  Notifications_Message,
}

method_name :: proc(m: Method) -> string {
  switch m {
  case .Server_Discover:
    return "server/discover"
  case .Tools_List:
    return "tools/list"
  case .Tools_Call:
    return "tools/call"
  case .Resources_List:
    return "resources/list"
  case .Resources_Templates_List:
    return "resources/templates/list"
  case .Resources_Read:
    return "resources/read"
  case .Subscriptions_Listen:
    return "subscriptions/listen"
  case .Prompts_List:
    return "prompts/list"
  case .Prompts_Get:
    return "prompts/get"
  case .Completion_Complete:
    return "completion/complete"
  case .Elicitation_Create:
    return "elicitation/create"
  case .Notifications_Tools_List_Changed:
    return "notifications/tools/list_changed"
  case .Notifications_Resources_List_Changed:
    return "notifications/resources/list_changed"
  case .Notifications_Resources_Updated:
    return "notifications/resources/updated"
  case .Notifications_Prompts_List_Changed:
    return "notifications/prompts/list_changed"
  case .Notifications_Subscriptions_Acknowledged:
    return "notifications/subscriptions/acknowledged"
  case .Notifications_Progress:
    return "notifications/progress"
  case .Notifications_Cancelled:
    return "notifications/cancelled"
  case .Notifications_Message:
    return "notifications/message"
  }
  return ""
}

method_from_name :: proc(s: string) -> (Method, bool) {
  for m in Method {
    if method_name(m) == s do return m, true
  }

  return {}, false
}

MCP_Specific_Error :: enum i64 {
  // HTTP headers don't match request body values
  Header_Mismatch                    = -32020,
  // Client lacks a required capability
  Missing_Required_Client_Capability = -32021,
  // Server doesn't support the requested protocol version
  Unsupported_Protocol_Version       = -32022,
}

Meta_Field :: enum {
  /****** Client -> Server (request `_meta`) ******/

  // Client's capabilities for this specific request. Required. Declared
  // per-request rather than once at initialization; an empty object means
  // the client supports no optional capabilities.
  Client_Capabilities,
  // Identifies the client software making the request. Self-reported, for
  // display, logging, and debugging.
  Client_Info,
  // Desired log level for this request. If absent, the server must not send
  // notifications/message for this request. Replaces the former
  // logging/setLevel RPC.
  Log_Level,
  // MCP protocol version used for this request. Required. On the HTTP
  // transport it must match the MCP-Protocol-Version header.
  Protocol_Version,
  // Requests out-of-band progress notifications for this request; the value
  // is an opaque token attached to any subsequent notifications/progress.
  Progress_Token,

  /****** Server -> Client (result `_meta`) ******/

  // Identifies the server software producing the response. Self-reported,
  // for display, logging, and debugging.
  Server_Info,

  /****** Notifications (one-way `_meta`) ******/

  // Identifies the subscription stream a notification was delivered on; the
  // value is the JSON-RPC id of the originating subscriptions/listen request.
  Subscription_Id,
}

meta_field_name :: proc(field: Meta_Field) -> string {
  switch field {
  case .Client_Capabilities:
    return "io.modelcontextprotocol/clientCapabilities"
  case .Client_Info:
    return "io.modelcontextprotocol/clientInfo"
  case .Log_Level:
    return "io.modelcontextprotocol/logLevel"
  case .Protocol_Version:
    return "io.modelcontextprotocol/protocolVersion"
  case .Progress_Token:
    return "progressToken"
  case .Server_Info:
    return "io.modelcontextprotocol/serverInfo"
  case .Subscription_Id:
    return "io.modelcontextprotocol/subscriptionId"
  }
  return ""
}

// A meta field whose value carries no data; its mere presence is the signal.
Empty :: struct {}

// Client's support for server elicitation requests.
Elicitation_Capabilities :: struct {
  // Whether the client supports form-based elicitation.
  form: Maybe(json.Object) `json:"form,omitempty"`,
  // Whether the client supports url-based elicitation.
  url:  Maybe(json.Object) `json:"url,omitempty"`,
}

// Value of the `io.modelcontextprotocol/clientCapabilities` meta key. Required;
// an empty object means the client supports no optional capabilities.
Client_Capabilities :: struct {
  // Present if the client supports filesystem roots.
  elicitation: Maybe(Elicitation_Capabilities) `json:"elicitation,omitempty"`,
}

// Value of the `io.modelcontextprotocol/clientInfo` and
// `io.modelcontextprotocol/serverInfo` meta keys.
Implementation :: struct {
  name:    string,
  version: string,
  title:   Maybe(string),
}

Client_Info :: Implementation
Server_Info :: Implementation

Tools_Capab :: struct {
  // This indicates whether the server will emit
  // notifications (`"notifications/tools/list_changed"`) when the list of available tools changes
  list_changed: Maybe(bool) `json:"listChanged,omitempty"`,
}
Resources_Capab :: struct {
  // This indicates whether the server will emit
  // notifications when the list of available resources changes
  list_changed: Maybe(bool) `json:"listChanged,omitempty"`,
  subscribe:    Maybe(bool) `json:"subscribe,omitempty"`,
}
Prompts_Capab :: struct {
  // This indicates whether the server will emit
  // notifications when the list of available prompts changes
  list_changed: Maybe(bool) `json:"listChanged,omitempty"`,
}

// Value of the `capabilities` in response to a `server/discover` request.
//
// `omitempty` will leave out the field if not set (a nil/null field). Meaning:
/*

      ```odin
        capabilities = {
			tools     = Tools_Capab{ list_changed = true },
			resources = Resources_Capab{}, 
		},
      ```

      will result in

      ```json
      {
        "capabilities": {
            "tools": { "list_changed": true },
            "resources": {},
        }
      }
      ```

      and NOT

      ```json
      {
        "capabilities": {
            "tools": { "list_changed": true },
            "resources": {},
            "prompts": null,
            "completions": null,
            "experimental": null,
            "extensions": null,
        }
      }
      ```
*/
// Will result in
Server_Capabilities :: struct {
  // Server that declare this MUST respond to `tools/list` requests with the set of tools currently available to the requesting client.
  tools:        Maybe(Tools_Capab) `json:"tools,omitempty"`,
  resources:    Maybe(Resources_Capab) `json:"resources,omitempty"`,
  prompts:      Maybe(Prompts_Capab) `json:"prompts,omitempty"`,
  completions:  Maybe(Empty) `json:"completions,omitempty"`,
  experimental: Maybe(json.Object) `json:"experimental,omitempty"`,
  extensions:   Maybe(json.Object) `json:"extensions,omitempty"`,
}

// Value of the `io.modelcontextprotocol/logLevel` meta key.
Logging_Level :: enum {
  Debug,
  Info,
  Notice,
  Warning,
  Error,
  Critical,
  Alert,
  Emergency,
}

// Value of the `io.modelcontextprotocol/protocolVersion` meta key.
Protocol_Version :: string

// Value of the `progressToken` meta key.
Progress_Token :: union {
  string,
  i64,
}

// Value of the `io.modelcontextprotocol/subscriptionId` meta key.
Request_Id :: union {
  string,
  i64,
}

// Value of the `resultType` field on a result, indicating how the client
// should parse the response.
Result_Type :: enum {
  // The request completed successfully and the result contains the final content.
  Complete,
  // The request requires additional input; the result contains instructions
  // for the client to provide that input before retrying the original request.
  Input_Required,
}

result_type_name :: proc(t: Result_Type) -> string {
  switch t {
  case .Complete:
    return "complete"
  case .Input_Required:
    return "input_required"
  }
  return ""
}

// Hint from the server indicating how long (in milliseconds) the client MAY
// cache this response before re-fetching. Semantics are analogous to HTTP
// Cache-Control max-age. If 0, the response SHOULD be considered immediately
// stale; if positive, the client SHOULD consider the result fresh for this
// many milliseconds after receiving the response.
TTL_ms :: u64

// Scope of a cached response, analogous to HTTP `Cache-Control: public` vs
// `Cache-Control: private`.
Cache_Scope :: enum {
  // The response does not contain user-specific data. Any client or
  // intermediary (e.g., shared gateway, caching proxy) MAY cache the response
  // and serve it across authorization contexts.
  Public,
  // The response MAY be cached and reused only within the same authorization
  // context. Caches MUST NOT be shared across authorization contexts (e.g., a
  // different access token requires a different cache).
  Private,
}

cache_scope_name :: proc(s: Cache_Scope) -> string {
  switch s {
  case .Public:
    return "public"
  case .Private:
    return "private"
  }
  return ""
}

Cache_Response_Fields :: struct {
  ttl_ms:      Maybe(TTL_ms) `json:"ttlMs,omitempty"`,
  // TODO: when cache_scope, validate that's either "public" or "private"
  cache_scope: Maybe(string) `json:"cacheScope,omitempty"`, // "public" or "private"
}

Theme :: enum {
  Light,
  Dark,
}

theme_name :: proc(t: Theme) -> string {
  switch t {
  case .Light:
    return "light"
  case .Dark:
    return "dark"
  }

  return ""
}

Icon :: struct {
  src:       string `json:"src"`,
  mime_type: Maybe(string) `json:"mimeType,omitempty"`,
  sizes:     Maybe([]string) `json:"sizes,omitempty"`,
  // TODO: when icon, validate that the them is either "light" or "dark"
  theme:     Maybe(string) `json:"theme,omitempty"`, // "light" or "dark"
}

Server_Discover_Response_Meta :: struct {
  server_info: Maybe(Server_Info) `json:"io.modelcontextprotocol/serverInfo,omitempty"`,
}

Server_Discover_Response :: struct {
  result_type:        string `json:"resultType"`,
  supported_versions: []Protocol_Version `json:"supportedVersions"`,
  capabilities:       Server_Capabilities,
  meta:               Server_Discover_Response_Meta `json:"_meta"`,
  using _:            Cache_Response_Fields,
}

Meta :: map[string]json.Value
No_Schema :: struct {}

Role :: enum {
  User,
  Assistant,
}

role_name :: proc(role: Role) -> string {
  switch role {
  case .User:
    return "user"
  case .Assistant:
    return "assistant"
  }

  return ""
}

Annotations :: struct {
  audience:      Maybe([]string) `json:"audience,omitempty"`, // role: either "user" or "assistant"
  priority:      Maybe(i64) `json:"priority,omitempty"`,
  last_modified: Maybe(string) `json:"lastModified,omitempty"`,
}

Cursor :: string

Content_Type :: enum {
  Text,
  Image,
  Audio,
}

Text_Content :: struct {
  type: string `json:"type"`, // "text"
  text: string `json:"text"`,
}

Media_Content :: struct {
  type:      string `json:"type"`, // "image" | "audio" etc
  data:      string `json:"data"`, // base64
  mime_type: string `json:"mimeType"`, // image/png, audio/wav etc
}

// TODO: include the rest of the contents
Content_Block :: union {
  Text_Content,
  Media_Content,
  // | ResourceLink
  // | EmbeddedResource
}

Subscription_Filter :: struct {
  tools_list_changed:     Maybe(bool) `json:"toolsListChanged,omitempty"`,
  prompts_list_changed:   Maybe(bool) `json:"promptsListChanged,omitempty"`,
  resources_list_changed: Maybe(bool) `json:"resourcesListChanged,omitempty"`,
  resource_subscriptions: Maybe([]string) `json:"resourceSubscriptions,omitempty"`,
}

Subscriptions_Listen_Request :: struct {
  meta:          Meta `json:"_meta,omitempty"`,
  notifications: Subscription_Filter `json:"notifications"`,
}

Subscriptions_Acknowledged_Notification_Params :: Subscriptions_Listen_Request

