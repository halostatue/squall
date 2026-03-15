import gleam/dynamic/decode
import gleam/http
import gleam/http/request.{type Request}
import gleam/json
import gleam/list
import gleam/result
import gleam/string

@target(erlang)
import argv

@target(erlang)
import squall/internal/generator

/// A GraphQL client with endpoint and headers configuration.
/// This client follows the sans-io pattern: it builds HTTP requests but doesn't send them.
/// You must use your own HTTP client to send the requests.
pub type Client {
  Client(endpoint: String, headers: List(#(String, String)))
}

/// Create a new GraphQL client with custom headers.
///
/// ## Example
///
/// ```gleam
/// let client = squall.new("https://api.example.com/graphql", [])
/// ```
pub fn new(endpoint: String, headers: List(#(String, String))) -> Client {
  Client(endpoint: endpoint, headers: headers)
}

/// Create a new GraphQL client with bearer token authentication.
///
/// ## Example
///
/// ```gleam
/// let client = squall.new_with_auth("https://api.example.com/graphql", "my-token")
/// ```
pub fn new_with_auth(endpoint: String, token: String) -> Client {
  Client(endpoint: endpoint, headers: [#("Authorization", "Bearer " <> token)])
}

/// Prepare an HTTP request for a GraphQL query.
/// This function builds the request but does not send it.
/// You must send the request using your own HTTP client.
///
/// ## Example
///
/// ```gleam
/// let client = squall.new("https://api.example.com/graphql", [])
/// let request = squall.prepare_request(
///   client,
///   "query { users { id name } }",
///   json.object([]),
/// )
///
/// // Send with your HTTP client (Erlang example)
/// let assert Ok(response) = httpc.send(request)
///
/// // Parse the response
/// let assert Ok(data) = squall.parse_response(response.body, your_decoder)
/// ```
pub fn prepare_request(
  client: Client,
  query: String,
  variables: json.Json,
) -> Result(Request(String), String) {
  let body =
    json.object([#("query", json.string(query)), #("variables", variables)])

  use req <- result.try(
    request.to(client.endpoint)
    |> result.map_error(fn(_) { "Invalid endpoint URL" }),
  )

  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_body(json.to_string(body))
    |> request.set_header("content-type", "application/json")

  let req =
    list.fold(client.headers, req, fn(r, header) {
      request.set_header(r, header.0, header.1)
    })

  Ok(req)
}

/// Parse a GraphQL response body using the provided decoder.
/// This function decodes the JSON response and extracts the data field.
///
/// ## Example
///
/// ```gleam
/// let decoder = decode.field("users", decode.list(user_decoder))
///
/// case squall.parse_response(response_body, decoder) {
///   Ok(users) -> io.println("Got users!")
///   Error(err) -> io.println("Parse error: " <> err)
/// }
/// ```
pub fn parse_response(
  body: String,
  decoder: decode.Decoder(a),
) -> Result(a, String) {
  use json_value <- result.try(
    json.parse(from: body, using: decode.dynamic)
    |> result.map_error(fn(_) { "Failed to decode JSON response" }),
  )

  let data_decoder = {
    use data <- decode.field("data", decoder)
    decode.success(data)
  }

  decode.run(json_value, data_decoder)
  |> result.map_error(fn(errors) {
    "Failed to decode response data: "
    <> string.inspect(errors)
    <> ". Response body: "
    <> body
  })
}

@target(erlang)
pub fn main() {
  generator.run(argv.load())
}
