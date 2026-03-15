import argv.{type Argv}
import envoy
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile
import squall/internal/codegen
import squall/internal/discovery
import squall/internal/error
import squall/internal/generator/introspection
import squall/internal/generator/usage
import squall/internal/graphql_ast.{type Operation}
import squall/internal/query_extractor
import squall/internal/registry_codegen
import squall/internal/schema
import squall/internal/typename_injector

pub fn run(argv: Argv) {
  case argv.arguments {
    ["generate", endpoint] -> generate(endpoint)
    ["generate"] -> generate_with_env()
    ["unstable-cache", endpoint] -> unstable_cache(endpoint)
    ["unstable-cache"] -> {
      io.println("Error: Endpoint required")
      io.println(usage.cache)
      Nil
    }
    _ -> {
      io.println(usage.long)
      Nil
    }
  }
}

fn generate_with_env() {
  io.println(usage.generate)
  Nil
}

fn generate(endpoint: String) {
  io.println("🌊 Squall - GraphQL Code Generator")
  io.println("=================================\n")
  io.println("📡 Introspecting GraphQL schema from: " <> endpoint)

  // Introspect schema
  case introspect_schema(endpoint) {
    Ok(schema_data) -> generate_files(endpoint, schema_data)
    Error(err) -> {
      io.println("✗ Schema introspection failed: " <> error.to_string(err))
      Nil
    }
  }
}

fn introspect_schema(endpoint: String) -> Result(schema.Schema, error.Error) {
  // Make HTTP request
  use response <- result.try(
    endpoint
    |> make_graphql_request(introspection.query, "")
    |> result.map_error(fn(err) { error.HttpRequestFailed(err) }),
  )

  // Parse schema
  schema.parse_introspection_response(response)
}

fn generate_files(endpoint: String, schema_data: schema.Schema) {
  io.println("✓ Schema introspected successfully\n")

  // Discover .gql files
  io.println("🔍 Discovering .gql files...")
  case discovery.find_graphql_files("src") {
    Ok(files) -> {
      io.println(
        "✓ Found " <> int.to_string(list.length(files)) <> " .gql file(s)\n",
      )

      // Process each file
      list.each(files, generate_file(_, endpoint, schema_data))

      io.println("\n✨ Code generation complete!")
      Nil
    }
    Error(err) -> {
      io.println("✗ Failed to discover files: " <> error.to_string(err))
      Nil
    }
  }
}

fn generate_file(
  file: discovery.GraphQLFile,
  endpoint: String,
  schema_data: schema.Schema,
) {
  io.println("📝 Processing: " <> file.path)

  case parse_and_get_operation(file.content) {
    Ok(#(operation, fragments)) -> {
      case
        codegen.generate_operation_with_fragments(
          file.operation_name,
          file.content,
          operation,
          fragments,
          schema_data,
          endpoint,
        )
      {
        Ok(code) -> {
          // Write generated code
          let output_path = string.replace(file.path, ".gql", ".gleam")

          case simplifile.write(output_path, code) {
            Ok(_) -> {
              io.println("  ✓ Generated: " <> output_path)
            }
            Error(_) -> {
              io.println("  ✗ Failed to write: " <> output_path)
            }
          }
        }
        Error(err) -> {
          io.println("  ✗ Code generation failed: " <> error.to_string(err))
        }
      }
    }
    Error(err) -> {
      io.println("  ✗ Parse failed: " <> error.to_string(err))
    }
  }
}

fn parse_and_get_operation(
  content: String,
) -> Result(#(Operation, List(Operation)), error.Error) {
  case graphql_ast.parse_document(content) {
    Ok(document) ->
      case graphql_ast.get_main_operation(document) {
        Ok(operation) ->
          Ok(#(operation, graphql_ast.get_fragment_definitions(document)))
        Error(error) -> Error(error)
      }

    Error(error) -> Error(error)
  }
}

fn get_auth_token() -> Result(String, Nil) {
  envoy.get("SQUALL_AUTH_TOKEN")
}

fn make_graphql_request(
  endpoint: String,
  query: String,
  variables: String,
) -> Result(String, String) {
  // Build JSON body
  let vars_value = case variables {
    "" -> json.object([])
    _ -> json.string(variables)
  }

  let body =
    json.object([#("query", json.string(query)), #("variables", vars_value)])
    |> json.to_string

  // Create HTTP request
  use req <- result.try(
    request.to(endpoint)
    |> result.map_error(fn(_) { "Invalid endpoint URL: " <> endpoint }),
  )

  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_body(body)
    |> request.set_header("content-type", "application/json")
    |> request.set_header("accept", "application/json")

  // Add auth header from SQUALL_AUTH_TOKEN env var if set
  let req = case get_auth_token() {
    Ok(token) -> request.set_header(req, "authorization", "Bearer " <> token)
    Error(_) -> req
  }

  // Send request using httpc (generator always runs on Erlang)
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(_) { "Failed to send HTTP request to " <> endpoint }),
  )

  // Check status code
  case resp.status {
    200 -> Ok(resp.body)
    _ ->
      Error(
        "HTTP request failed with status "
        <> int.to_string(resp.status)
        <> ": "
        <> resp.body,
      )
  }
}

fn unstable_cache(endpoint: String) {
  let queries_output_dir = "src/generated/queries"
  let registry_output_path = "src/generated/queries.gleam"

  io.println("🌊 Squall")
  io.println("============================================\n")

  io.println("🔍 Scanning for GraphQL queries in src/...")

  // Scan for component files
  case query_extractor.scan_component_files("src") {
    Ok(files) -> {
      io.println(
        "✓ Found " <> int.to_string(list.length(files)) <> " .gleam file(s)\n",
      )

      // Extract queries from each file
      io.println("📝 Extracting queries...")
      let all_queries =
        list.fold(files, [], fn(acc, file_path) {
          case query_extractor.extract_from_file(file_path) {
            Ok(queries) -> {
              list.each(queries, fn(q) {
                io.println("  ✓ Found: " <> q.name <> " in " <> file_path)
              })
              list.append(acc, queries)
            }
            Error(err) -> {
              io.println(
                "  ✗ Failed to extract from " <> file_path <> ": " <> err,
              )
              acc
            }
          }
        })

      case list.length(all_queries) {
        0 -> {
          io.println("\n⚠ No GraphQL queries found")
          io.println(
            "Add GraphQL query blocks to your doc comments with named operations",
          )
          Nil
        }
        _ -> {
          io.println(
            "\n✓ Extracted "
            <> int.to_string(list.length(all_queries))
            <> " quer"
            <> case list.length(all_queries) {
              1 -> "y"
              _ -> "ies"
            },
          )

          // Introspect schema
          io.println("\n📡 Introspecting GraphQL schema from: " <> endpoint)
          case introspect_schema(endpoint) {
            Ok(schema_data) -> {
              io.println("✓ Schema introspected successfully\n")

              // Generate type-safe code for each query
              io.println("🔧 Generating type-safe code...")
              list.each(all_queries, fn(query_def) {
                io.println("  • " <> query_def.name)

                // Parse the GraphQL query
                case parse_and_get_operation(query_def.query) {
                  Ok(#(operation, fragments)) -> {
                    // Generate code - convert query name to snake_case for module name
                    let module_name = to_snake_case(query_def.name)

                    case
                      codegen.generate_operation_with_fragments(
                        module_name,
                        query_def.query,
                        operation,
                        fragments,
                        schema_data,
                        endpoint,
                      )
                    {
                      Ok(code) -> {
                        let file_name = module_name
                        let module_path =
                          queries_output_dir <> "/" <> file_name <> ".gleam"

                        // Create directory if needed
                        let _ =
                          simplifile.create_directory_all(queries_output_dir)

                        case simplifile.write(module_path, code) {
                          Ok(_) -> io.println("    ✓ " <> module_path)
                          Error(_) ->
                            io.println("    ✗ Failed to write " <> module_path)
                        }
                      }
                      Error(err) -> {
                        io.println(
                          "    ✗ Codegen failed: " <> error.to_string(err),
                        )
                      }
                    }
                  }
                  Error(err) -> {
                    io.println("    ✗ Parse failed: " <> error.to_string(err))
                  }
                }
              })

              // Generate registry code with __typename injected
              io.println("\n📦 Generating registry module...")
              // Inject __typename into all query strings for the registry
              let queries_with_typename =
                list.map(all_queries, fn(query_def) {
                  case
                    typename_injector.inject_typename(
                      query_def.query,
                      schema_data,
                    )
                  {
                    Ok(injected_query) ->
                      query_extractor.QueryDefinition(
                        name: query_def.name,
                        query: injected_query,
                        file_path: query_def.file_path,
                      )
                    Error(_) -> query_def
                  }
                })
              let code =
                registry_codegen.generate_registry_module(queries_with_typename)

              // Write to output file
              case simplifile.write(registry_output_path, code) {
                Ok(_) -> {
                  io.println("✓ Generated: " <> registry_output_path)
                  io.println("\n✨ Code generation complete!")
                  Nil
                }
                Error(_) -> {
                  io.println("✗ Failed to write: " <> registry_output_path)
                  Nil
                }
              }
            }
            Error(err) -> {
              io.println(
                "✗ Schema introspection failed: " <> error.to_string(err),
              )
              Nil
            }
          }
        }
      }
    }
    Error(err) -> {
      io.println("✗ Failed to scan files: " <> err)
      Nil
    }
  }
}

fn to_snake_case(s: String) -> String {
  // Simple conversion: GetCharacters -> get_characters
  s
  |> string.to_graphemes()
  |> list.index_fold([], fn(acc, char, index) {
    case is_uppercase(char) {
      True ->
        case index {
          0 -> list.append(acc, [string.lowercase(char)])
          _ -> list.append(acc, ["_", string.lowercase(char)])
        }
      False -> list.append(acc, [char])
    }
  })
  |> string.join("")
}

fn is_uppercase(s: String) -> Bool {
  s == string.uppercase(s) && s != string.lowercase(s)
}
