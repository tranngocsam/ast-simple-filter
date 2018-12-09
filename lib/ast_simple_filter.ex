defmodule AstSimpleFilter do
  @moduledoc """
    Provide `eq`, `neq`, `lt`, `lte`, `gt`, `gte`, `nil`, `in`, `nin` for fields of any model.

    Define `:<model>_custom_fields` type, which returns all fields of the `<model>`

    Define `:<model>_filter_input` input, which allows to add `<column_name>_(eq|in|nin|...)`

    Define `asf_filter/2` functions, which allows to filter `<Model>` by the `<model>_filter_input`

  ## Examples

    `use AstSimpleFilter.DefineTypes, base_name: :user, field_types: [%{field: id, type: :id}, %{field: age, type: :integer}, %{field: email, type: :string}]`

    Will define

    ```
      object :user_custom_fields do
        field :id, :id,
        field :age, :integer
        field :email, :string
      end

      object :user_results do
        field :data, list_of(:user_custom_fields)
        field :meta, :asf_pagination_info
      end
    ```

    `use AstSimpleFilter.DefineFilterInput, base_name: :user, field_types: [%{field: id, type: :id}, %{field: age, type: :integer}, %{field: email, type: :string}]`

    Will define: 

    ```
      input_object :user_filter_input do
        field age_eq, :integer
        field age_neq, :integer
        field age_lt, :integer
        field age_lte, :integer
        field age_gt, :integer
        field age_gte, :integer
        field age_in, list_of(:integer)
        field age_nin, list_of(:integer)
        field age_nil, :boolean
      end
    ```
  """
  defmodule DefineCommonObjects do
    @moduledoc """
      Define default input, object that are used in the DefineTypes module.

      Define `:asf_pagination_info` object, which contains `total` entries, `page_number` and `per_page`.

      Define `:ast_pagination_input` input, which allows to specify `page_number` and `per_page`.

    ## Usage: 
    
      in `data_types.ex` add

      `use AstSimpleFilter.DefineCommonObjects`
    """

    use Absinthe.Schema.Notation

    defmacro __using__(_) do
      apply(__MODULE__, :define_output, [])
    end

    def define_output do
      quote do
        object :asf_pagination_info do
          field :total, :integer
          field :page_number, :integer
          field :per_page, :integer
        end

        input_object :asf_pagination_input do
          field :page, :integer
          field :per_page, :integer
        end

        scalar :asf_uuid, name: "AsfUUID" do
          serialize fn(value)->
            if is_bitstring(value) do
              {:ok, uuid} = Ecto.UUID.cast(value)
              uuid
            else
              value
            end
          end

          parse fn(value_param)->
            if value_param.__struct__ == Absinthe.Blueprint.Input.String do
              value = value_param.value

              Ecto.UUID.dump(value)
            else
              value_param
            end
          end
        end

        scalar :asf_json, name: "AsfJson" do
          serialize fn(value)->
            value
          end

          parse fn(value_param)->
            if value_param.__struct__ == Absinthe.Blueprint.Input.String do
              value = value_param.value

              case Jason.decode(value) do
                {:ok, result} -> {:ok, result}
                _ -> :error
              end
            else
              value_param
            end
          end
        end
      end
    end
  end

  defmodule DefineTypes do
    @moduledoc """
      Define returned objects that can be used in absinthe.

      Define `:<model>_custom_fields`, which allows to customize returned fields

      Define `:<model>_results`, which allows to return additional data (Default is `asf_pagination_info`)

    ## Example
      In `data_types.ex` add

      `use AstSimpleFilter.DefineTypes, base_name: :user, field_types: [%{field: id, type: :id}, %{field: age, type: :integer}, %{field: email, type: :string}]`

      Will define

      ```
        object :user_custom_fields do
          field :id, :id
          field :page, :integer
          field :email, :string
        end

        object :user_results do
          field :data, list_of(:user_custom_fields)
          field :meta, :asf_pagination_info
        end
      ```

      We can omit `field_types` and use `kclass` instead, ie `use AstSimpleFilter.DefineTypes, base_name: :user, kclass: Demo.Accounts.User`, in this case it will use all fields (Exclude virtual fields) of Demo.Accounts.User.
      Other optional parameters are `custom_datetime_type`, `custom_date_type`, `custom_meta_type`. We need to define common objects (`DefineCommonObjects`) if these optional parameter are omited. 
    """

    use Absinthe.Schema.Notation
    
    defmacro __using__(opts) do
      field_types = if !opts[:field_types] do
        kclass = Macro.expand(opts[:kclass], __ENV__)
        fields = kclass.__schema__(:fields)
        Enum.map(fields, fn(f)->
          %{field: f, type: kclass.__schema__(:type, f)}
        end)
      else
        {field_types, _} = Module.eval_quoted(__CALLER__, opts[:field_types])
        field_types
      end

      args = %{
        base_name: opts[:base_name],
        field_types: field_types,
        model_object: opts[:model_object],
        custom_datetime_type: opts[:custom_datetime_type],
        custom_date_type: opts[:custom_date_type],
        custom_meta_type: opts[:custom_meta_type]
      }

      apply(__MODULE__, :define_output, [args])
    end

    def define_output(opts) do
      base_name = opts[:base_name]
      field_types = opts[:field_types]
      model_results = String.to_atom("#{base_name}_results")
      model_custom_fields = String.to_atom("#{base_name}_custom_fields")
      model_object = opts[:model_object] || model_custom_fields
      custom_datetime_type = opts[:custom_datetime_type] || :naive_datetime
      custom_date_type = opts[:custom_date_type] || :date
      custom_meta_type = opts[:custom_meta_type] || :asf_pagination_info

      asts = Enum.map(field_types, fn(field_type)-> 
        f_name = field_type[:field]
        f_type = field_type[:type]

        f_type = if f_type == :naive_datetime do
          custom_datetime_type
        else
          if f_type == :date do
            custom_date_type
          else
            if f_type == :binary_id || f_type == :uuid do
              :asf_uuid
            else
              if f_type == :map do
                :asf_json
              else
                f_type
              end
            end
          end
        end

        quote do
          field unquote(f_name), unquote(f_type)
        end      
      end)
      
      quote do
        object unquote(model_custom_fields) do
          unquote(asts)
        end

        object unquote(model_results) do
          field :data, list_of(unquote(model_object))
          field :meta, unquote(custom_meta_type)
        end
      end
    end
  end

  defmodule DefineFilterInput do
    @moduledoc """
      Define `:<model>_filter_input`, which has `id_eq, id_neq,...`

    ## Example 
      In `data_types.ex` add

      `use AstSimpleFilter.DefineFilterInput, base_name: :user, field_types: [%{field: id, type: :id}, %{field: age, type: :integer}, %{field: email, type: :string}]`

      Will define

      ```
        input_object :user_filter_input do
          field :id_eq, :id
          field :id_neq, :id
          field :id_in, list_of(:id)
          field :id_nin, list_of(:id)
          field :id_nil, :boolean
          field :id_lt, :id
          field :id_lte, :id
          field :id_gt, :id
          field :id_gte, :id

          field :age_eq, :integer
          field :age_neq, :integer
          field :age_in, list_of(:integer)
          field :age_nin, list_of(:integer)
          field :age_nil, :boolean
          field :age_lt, :integer
          field :age_lte, :integer
          field :age_gt, :integer
          field :age_gte, :integer

          field :email_eq, :string
          field :email_neq, :string
          field :email_in, list_of(:string)
          field :email_nin, list_of(:string)
          field :email_nil, :boolean
          field :email_lt, :string
          field :email_lte, :string
          field :email_gt, :string
          field :email_gte, :string
        end
      ```

      Similarly, we can omit `field_types` and use `kclass` instead, ie `use AstSimpleFilter.DefineFilterInput, base_name: :user, kclass: Demo.Accounts.User`, in this case it will define filters for all fields (Exclude virtual fields) of Demo.Accounts.User
    """
    use Absinthe.Schema.Notation
    
    defmacro __using__(opts) do
      base_name = opts[:base_name]
      field_types = if !opts[:field_types] do
        kclass = Macro.expand(opts[:kclass], __ENV__)
        fields = kclass.__schema__(:fields)
        Enum.map(fields, fn(f)->
          %{field: f, type: kclass.__schema__(:type, f)}
        end)
      else
        {field_types, _} = Module.eval_quoted(__CALLER__, opts[:field_types])
        field_types
      end

      field_types = Enum.reject(field_types, fn(f)->
        f[:type] == :map
      end)

      args = %{
        base_name: base_name,
        field_types: field_types
      }

      apply(__MODULE__, :define_input, [args])
    end

    def define_input(opts) do
      base_name = opts[:base_name]
      field_types = opts[:field_types]
      input_name = String.to_atom("#{base_name}_filter_input")

      asts = Enum.map(field_types, fn(field_type)->
        f_name = field_type[:field]
        f_type = field_type[:type]

        f_type = if f_type == :naive_datetime do
          :string
        else
          if f_type == :binary_id do
            :asf_uuid
          else
            f_type
          end
        end

        suffixes = if f_type == :boolean do
          ["eq", "neq", "in", "nin", "nil"]
        else
          ["eq", "neq", "in", "nin", "gt", "gte", "lt", "lte", "nil"]
        end 

        Enum.map(suffixes, fn(suffix)-> 
          full_field_name = String.to_atom("#{f_name}_#{suffix}")

          f_type = if suffix == "nil" do
            :boolean
          else
            f_type
          end

          if suffix == "in" || suffix == "nin" do
            quote do
              field unquote(full_field_name), list_of(unquote(f_type))
            end
          else
            quote do
              field unquote(full_field_name), unquote(f_type)
            end
          end
        end)
      end)

      quote do
        input_object unquote(input_name) do
          unquote(asts)
        end
      end
    end
  end

  defmodule DefineFilterFunctions do
    @moduledoc """
      Define `asf_filter/2`, `asf_filter/3` functions that can be used to filter `<Model>` by `<model>_filter_input`.

    ## Example: 
      In `User` model add
    
      `use AstSimpleFilter.DefineFilterFunctions, Demo.Accounts.User`

      Then we can use

      ```
        query = from u in "users", select: map(u, [:id, :age, :email])
        User.asf_filter(query, %{idEq: 1})
      ```
    """
    defmacro __using__(opts) do
      field_types = if opts[:field_types] do
        {field_types, _} = Module.eval_quoted(__CALLER__, opts[:field_types])
        field_types
      end

      args = %{
        klass: opts[:klass],
        field_types: field_types
      }

      apply(__MODULE__, :define_filter_fns, [args])
    end

    def define_filter_fns(opts) do
      module = Macro.expand(opts[:klass], __ENV__)
      field_types = opts[:field_types]

      quote do
        def asf_filter(query, nil, _) do
          query
        end

        def asf_filter(query, fieldname_param, value) do
          matches = extract_fieldname_and_operator(fieldname_param)

          if length(matches) != 2 do
            raise ArgumentError, message: "invalid field parameter #{fieldname_param}"
          end

          fieldname = String.to_atom(Enum.at(matches, 0))
          operator = Enum.at(matches, 1)

          fields_arr = unquote(Macro.escape(field_types))

          type = if fields_arr && length(fields_arr) > 0 do
            field = Enum.find(fields_arr, fn(el)->
              el[:field] == fieldname
            end)

            field[:type]
          else
            unquote(module).__schema__(:type, fieldname)
          end

          if is_nil(type) do
            raise ArgumentError, message: "invalid field name #{fieldname}"
          end

          type = if operator == "nil" do
            :boolean
          else
            type
          end

          refined_value = refine_value_for_db_type(type, value)

          # NOTE: value must be in correct type.
          dynamic_query = case operator do
            "eq" ->
              dynamic([q], field(q, ^fieldname) == ^refined_value)
            "neq" ->
              dynamic([q], field(q, ^fieldname) != ^refined_value)
            "in" ->
              dynamic([q], field(q, ^fieldname) in ^List.flatten([refined_value]))
            "nin" ->
              dynamic([q], field(q, ^fieldname) not in ^List.flatten([refined_value]))
            "gt" ->
              dynamic([q], field(q, ^fieldname) > ^refined_value)
            "gte" ->
              dynamic([q], field(q, ^fieldname) >= ^refined_value)
            "lt" ->
              dynamic([q], field(q, ^fieldname) < ^refined_value)
            "lte" ->
              dynamic([q], field(q, ^fieldname) <= ^refined_value)
            "nil" ->
              if refined_value == true do
                dynamic([q], is_nil(field(q, ^fieldname)))
              else
                dynamic([q], not is_nil(field(q, ^fieldname)))
              end
            _->
              raise "unimplemented"
          end

          query |> where(^dynamic_query)
        end

        def asf_filter(query, %{} = params) do
          Enum.reduce(params, query, fn({k, v}, modified_query)-> asf_filter(modified_query, k, v) end)
        end

        def asf_filter(query, _) do
          query
        end

        def filter_field(dynamic, nil, _) do
          dynamic
        end

        def filter_field(dynamic, fieldname, value) do
          dynamic([q], field(q, ^fieldname) == ^value or ^dynamic)
        end

        def refine_value_for_db_type(type, value) do
          if is_list(value) do
            Enum.map(value, fn(v)-> refine_value_for_db_type(type, v) end)
          else
            if is_binary(value) do
              if type == :boolean do
                if value == "" do
                  nil
                else 
                  if String.downcase(value) == "true" do
                    true
                  else
                    false
                  end
                end
              else 
                if type == :id || type == :integer || type == :float do
                  if value == "" do
                    nil
                  else 
                    if type == :id || type == :integer do
                      String.to_integer(value)
                    else
                      Float.parse(value)
                    end
                  end
                else
                  if type == :naive_datetime do
                    {status, parsed_value} = Timex.parse(value, "%Y-%m-%d %H:%M:%S", :strftime)

                    if status == :ok do
                      parsed_value
                    else
                      {:ok, parsed_value} = Timex.parse(value, "%Y-%m-%d", :strftime)
                      parsed_value
                    end
                  else
                    value
                  end
                end
              end
            else
              value
            end
          end
        end

        def extract_fieldname_and_operator(fieldname_param) do
          Regex.scan(~r/([a-z_]+)_(eq|neq|in|nin|lt|lte|gt|gte|nil)$/i, inspect(fieldname_param))
                      |> List.flatten
                      |> List.delete_at(0)
        end
      end
    end
  end
end
