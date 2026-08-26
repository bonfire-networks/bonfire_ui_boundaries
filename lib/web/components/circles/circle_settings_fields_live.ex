defmodule Bonfire.UI.Boundaries.CircleSettingsFieldsLive do
  @moduledoc "Shared fields for creating and editing a circle."
  use Bonfire.UI.Common.Web, :stateless_component

  prop id_prefix, :string, required: true
  prop form, :any, required: true
end
