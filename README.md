# AstSimpleFilter


When start working with Absinthe, I want to add the ability to filter a given model by any fields using `eq`, `lt`, `gt`, `in`,...

So I created this package, it does 2 things:

1. Allow to add `filters` and `pagination` parameters to GraphQL query.

2. Allow to filter a model using the above `filters` parameter

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/ast_simple_filter](https://hexdocs.pm/ast_simple_filter).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ast_simple_filter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ast_simple_filter, "~> 0.0.1"}
  ]
end
```

## Usage

### Add `filter`

#### Define some common types (Optional):

`use AstSimpleFilter.DefineCommonObjects`

This will define:

`:asf_datetime` scalar to use for datetime fields.

`:asf_date` scalar to use for date fields.

`:asf_pagination_info` object, which contains `total` entries, `page_number` and `per_page`.

`:ast_pagination_input` input, which allows to specify `page_number` and `per_page`.

#### Define output (Optional)

`use AstSimpleFilter.DefineTypes, base_name: :<base_name>, field_types: <field_types_list>, custom_datetime_type: :<custom_datetime_type>, :custom_date_type: :<custom_date_type>, custom_meta_type: :<custom_meta_type>`

Example of a `<field_types_list>` is: `[{id: :id}, {age: :integer}, {email: :string}]`. We can replace `field_types: [...]` by `kclass: <Model>`, in this case, it will include all fields of `<Model>` into `<base_name>_custom_fields`, If we omit `custom_datetime_type: :<custom_datetime_type>, :custom_date_type: <custom_date_type>, custom_meta_type: <custom_meta_type>`, then we need to define common types first (Step above).

This will define 2 objects:

 `:<base_name>_custom_fields`

 ```
  object :<base_name>_results do
    field :data, list_of(:<base_name>_custom_fields)
    field :meta, :asf_pagination_info (or :custom_meta_type)
  end
 ```

#### Define filter input

`use AstSimpleFilter.DefineFilterInput, base_name: :<base_name>, field_types: <field_types_list>`

Example of a `<field_types_list>` is: `[{id: :id}, {age: :integer}, {email: :string}]`. Again, we can replace `field_types: [...]` by `kclass: <Model>`

This will define an input like this:

```
  input_object user_filter_input do
    field age_eq :integer
    field age_neq :integer
    field age_lt :integer
    field age_lte :integer
    field age_gt :integer
    field age_gte :integer
    field age_in list_of(:integer)
    field age_nin list_of(:integer)
    field age_nil :boolean
  end
```

Then we can define query like this

```
  query do
    @desc "Get a list of users"
    field :users, :user_results do
      arg(:filters, :user_filter_input)
      arg(:pagination, :asf_pagination_input)
      resolve fn _parent, args, resolution ->
        ...
      end
    end
  end
```

### Add `asf_filter` function

In `<model>` add:

```
import Ecto.Query
use AstSimpleFilter.DefineFilterFunctions, <Model>
```

This will define `asf_filter(%{})` function, which accept the `arg.filters` to filter `<Model>`
Note that because the `asf_filter` use `Ecto.Query`, so we need to import it first.

## Example

https://github.com/tranngocsam/absinthe-simple-filter