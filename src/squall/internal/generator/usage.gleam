pub const generate = "Usage: gleam run -m squall generate <endpoint>"

pub const cache = "Usage: gleam run -m squall unstable-cache <endpoint>"

pub const long = "
Squall - Type-safe GraphQL client generator for Gleam

Usage:
  gleam run -m squall generate <endpoint>
  gleam run -m squall unstable-cache <endpoint>


Commands:
  generate <endpoint>         Generate Gleam code from .gql files
  unstable-cache <endpoint>   Extract GraphQL queries from doc comments
                              and generate types and cache registry

generate:

  1. Finds all .gql files in src/**/graphql/ directories
  2. Introspects the GraphQL schema from the endpoint
  3. Generate type-safe Gleam functions for each query, mutation,
     and subscription

unstable-cache:
  1. Scan all .gleam files in src/ for GraphQL query blocks in doc
     comments
  2. Introspect the GraphQL schema from the endpoint
  3. Automatically inject __typename into queries for cache
     normalization
  4. Generate type-safe code for each query at src/generated/queries/
  5. Generate a registry initialization module at
     src/generated/queries.gleam

Authenticated Endpoints:

If your endpoint requires bearer authentication, it can be provided
using $SQUALL_AUTH_TOKEN.


Examples:
  gleam run -m squall generate https://rickandmortyapi.com/graphql
  gleam run -m squall unstable-cache \\
    https://rickandmortyapi.com/graphql

  SQUALL_AUTH_TOKEN=$(gh auth token) gleam run -m squall \\
    generate https://api.github.com/graphql
"
