import gleam/http/request
import gleam/io
import gleam/result

import envoy
import squall

// Import the generated GraphQL code
import graphql/starred_repos

// import graphql/user_starred_repos

// For Erlang target (default)
@target(erlang)
import gleam/httpc

@target(javascript)
import gleam/fetch
@target(javascript)
import gleam/javascript/promise

pub fn main() {
  let assert Ok(token) = envoy.get("GH_TOKEN")
  let client = squall.new_with_auth("https://api.github.com/graphql", token)

  io.println("=== Simple Query ===")
  let assert Ok(request) = starred_repos.starred_repos(client, "")

  request
  |> send()
  |> print()
}

// ==================== ERLANG HTTP CLIENT ====================
@target(erlang)
fn send(request: request.Request(String)) -> Result(String, String) {
  httpc.send(request)
  |> result.map(fn(resp) { resp.body })
  |> result.map_error(fn(_) { "HTTP request failed" })
}

@target(javascript)
fn send(
  request: request.Request(String),
) -> promise.Promise(Result(String, String)) {
  fetch.send(request)
  |> promise.try_await(fetch.read_text_body)
  |> promise.map(fn(result) {
    result
    |> result.map(fn(resp) { resp.body })
    |> result.map_error(fn(_) { "HTTP request failed" })
  })
}

@target(erlang)
fn print(result: Result(String, String)) {
  let assert Ok(body) = result
  io.println(body)
}

@target(javascript)
fn print(promised_result: promise.Promise(Result(String, String))) {
  promise.tap(promised_result, fn(result) {
    let assert Ok(body) = result
    io.println(body)
  })
}
