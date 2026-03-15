pub const query = "
    query IntrospectionQuery {
      __schema {
        queryType { name }
        mutationType { name }
        subscriptionType { name }
        types {
          name
          kind
          description
          fields {
            name
            description
            type {
              ...TypeRef
            }
            args {
              name
              type {
                ...TypeRef
              }
            }
          }
          inputFields {
            name
            type {
              ...TypeRef
            }
          }
          enumValues {
            name
          }
          possibleTypes {
            name
          }
        }
      }
    }

    fragment TypeRef on __Type {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
              }
            }
          }
        }
      }
    }
  "

pub fn q() -> String {
  query
}
