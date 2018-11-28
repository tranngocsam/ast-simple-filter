defmodule AstSimpleFilterTest do
  use ExUnit.Case
  doctest AstSimpleFilter

  test "module DefineCommonObjects" do
    defmodule TestDataTypes do
      use Absinthe.Schema.Notation
      import_types Absinthe.Type.Custom
      use AstSimpleFilter.DefineCommonObjects
    end
    
    defmodule TestSchema do
      use Absinthe.Schema
      import_types TestDataTypes

      query do
        field :sample_input, :integer
      end

      def has_pagination_info do
        is_atom(:asf_pagination_info)
      end

      def has_pagination_input do
        is_atom(:asf_pagination_input)
      end
    end

    assert TestSchema.has_pagination_info
    assert TestSchema.has_pagination_input
  end

  test "module DefineTypes" do
    defmodule TestDefineTypes do
      use Absinthe.Schema.Notation
      import_types Absinthe.Type.Custom
      
      object :extra_info do
        field :total, :integer
        field :page_number, :integer
        field :per_page, :integer
      end

      use AstSimpleFilter.DefineTypes, base_name: :user, field_types: [%{field: :id, type: :id}, %{field: :age, type: :integer}, %{field: :email, type: :string}], custom_meta_type: :extra_info
    end
    
    defmodule TestSchema do
      use Absinthe.Schema
      import_types TestDefineTypes

      query do
        field :sample_input, :integer
      end

      def has_user_custom_fields do
        is_atom(:user_custom_fields)
      end

      def has_user_results do
        is_atom(:user_results)
      end
    end

    assert TestSchema.has_user_custom_fields
    assert TestSchema.has_user_results
  end

  test "module DefineFilterInput" do
    defmodule TestDefineFilterInput do
      use Absinthe.Schema.Notation
      import_types Absinthe.Type.Custom
      
      use AstSimpleFilter.DefineFilterInput, base_name: :user, field_types: [%{field: :id, type: :id}, %{field: :age, type: :integer}, %{field: :email, type: :string}]
    end
    
    defmodule TestSchema do
      use Absinthe.Schema
      import_types TestDefineFilterInput

      query do
        field :sample_input, :integer
      end

      def has_user_filter_input do
        is_atom(:user_filter_input)
      end
    end

    assert TestSchema.has_user_filter_input
  end

  test "module DefineFilterFunctions" do
    defmodule TestUser do
      use Ecto.Schema
      import Ecto.Query

      use AstSimpleFilter.DefineFilterFunctions, AstSimpleFilterTest.TestUser

      schema "test_users" do
        field :age, :integer
        field :email, :string

        timestamps()
      end
    end

    assert :erlang.function_exported(TestUser, :asf_filter, 2)
  end
end
