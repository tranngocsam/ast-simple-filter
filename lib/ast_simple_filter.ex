defmodule AstSimpleFilter do
  defmodule DefineCommonTypesAndScalars do
    use Absinthe.Schema.Notation

    defmacro __using__(_) do
      apply(__MODULE__, :define_output, [])
    end

    def define_output do
      quote do
        scalar :datetime_asf, name: "DateTimeAsf" do
          serialize fn(value)->
            if is_tuple(value) do
              {{year, month, date}, {hour, minute, second, after_second}} = value
              "#{year}-#{month}-#{date} #{hour}:#{minute}:#{second}.#{after_second}"
            else
              DateTime.to_iso8601(value)
            end
          end

          parse fn(value)->
            Timex.parse(value, "%Y-%m-%d %H:%M:%S.%6N", :strftime)
          end
        end

        scalar :date_asf, name: "DateAsf" do
          serialize fn(value)->
            if is_tuple(value) do
              {year, month, date} = value
              "#{year}-#{month}-#{date}"
            else
              DateTime.to_iso8601(value)
            end
          end

          parse fn(value)->
            Timex.parse(value, "%Y-%m-%d", :strftime).to_date
          end
        end

        object :ast_page_info do
          field :total, :integer
          field :page_number, :integer
          field :per_page, :integer
        end
      end
    end
  end

  defmodule DefineTypes do
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
        custom_datetime_type: opts[:custom_datetime_type],
        custom_date_type: opts[:custom_date_type]
      }

      apply(__MODULE__, :define_output, [args])
    end

    def define_output(opts) do
      base_name = opts[:base_name]
      field_types = opts[:field_types]
      model_results = String.to_atom("#{base_name}_results")
      model_custom_fields = String.to_atom("#{base_name}_custom_fields")
      custom_datetime_type = opts[:custom_datetime_type] || :datetime_asf
      custom_date_type = opts[:custom_date_type] || :date_asf
      custom_meta_type = opts[:custom_meta_type] || :ast_page_info

      asts = Enum.map(field_types, fn(field_type)-> 
        f_name = field_type[:field]
        f_type = field_type[:type]

        f_type = if f_type == :naive_datetime do
          custom_datetime_type
        else
          if f_type == :date do
            custom_date_type
          else
            f_type
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
          field :data, list_of(unquote(model_custom_fields))
          field :meta, unquote(custom_meta_type)
        end
      end
    end
  end

  defmodule DefineFilterInput do
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
          f_type
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
    defmacro __using__(model) do
      apply(__MODULE__, :define_filter_fns, [model])
    end

    def define_filter_fns(model) do
      module = Macro.expand(model, __ENV__)

      quote do
        def filter(query, nil, _) do
          query
        end

        def filter(query, fieldname_param, value) do
          matches = extract_fieldname_and_operator(fieldname_param)

          if length(matches) != 2 do
            raise ArgumentError, message: "invalid field parameter #{fieldname_param}"
          end

          fieldname = String.to_atom(Enum.at(matches, 0))
          operator = Enum.at(matches, 1)
          type = unquote(module).__schema__(:type, fieldname)

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

        def filter(query, %{} = params) do
          Enum.reduce(params, query, fn({k, v}, modified_query)-> filter(modified_query, k, v) end)
        end

        def filter(query, _) do
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
