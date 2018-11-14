# AstSimpleFilter

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ast_simple_filter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ast_simple_filter, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/ast_simple_filter](https://hexdocs.pm/ast_simple_filter).

  @moduledoc """
    Provide filter input for any models.
  """

  @doc """
  Define <model>_custom_fields type, which returns all fields of the <model>
  Define <model>_filter_input input, which allows to add <column_name>_(eq|in|nin|...)
  Difine filter function, which allows to filter <Model> by the <model>_filter_input

  ## Examples
    `use AstSimpleFilter.DefineTypes, base_name: :user, field_types: Demo.Accounts.User.filter_fields`
    Will define
    `:user_custom_fields` type
    ```
      object :user_results do
        field :data, list_of(:user_custom_fields)
        field :meta, :ast_page_info
      end

      object :ast_page_info do
        field :total, :integer
        field :current_page, :integer
        field :per_page, :integer
      end
    ```

    `use AstSimpleFilter.DefineFilterInput, base_name: :user, field_types: Demo.Accounts.User.filter_fields`
    Will define: 
    ```
      input_object user_filter_input do
        field age_eq :integer
        field age_neq :integer
        field age_lt :integer
        field age_lte :integer
        field age_gt :integer
        field age_gte :integer
        field age_in :string
        field age_nin :string
        field age_nil :boolean
      end
    ```
  """
