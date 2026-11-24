defmodule Bonfire.UI.Boundaries.Routes do
  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/" do
        pipe_through(:browser)

        # live("/list/:id", Bonfire.UI.Boundaries.ListPageLive,
        #   as: Bonfire.Data.AccessControl.Circle
        # )

        live("/circle/:id", Bonfire.UI.Boundaries.CircleLive,
          as: Bonfire.Data.AccessControl.Circle
        )

        live("/circle/:id/:tab", Bonfire.UI.Boundaries.CircleLive)
      end

      # circles page
      scope "/" do
        pipe_through(:browser)
        pipe_through(:user_required)

        live("/circles", Bonfire.UI.Boundaries.MyCirclesPageLive)
      end

      if extension_enabled?(:bonfire_ui_me) do
        # pages only guests can view
        scope "/settings/boundaries", Bonfire.UI.Boundaries do
          pipe_through(:browser)
          pipe_through(:guest_only)
        end

        # pages you need an account to view
        scope "/settings/boundaries", Bonfire.UI.Boundaries do
          pipe_through(:browser)
          pipe_through(:account_required)
        end

        # pages you need to view as a user
        scope "/settings/boundaries", Bonfire.UI.Boundaries do
          pipe_through(:browser)
          pipe_through(:user_required)

          live("/scope/:scope", BoundariesLive, as: :boundaries)
          live("/scope/:scope/:tab", BoundariesLive, as: :boundaries)
          live("/scope/:scope/:tab/:id", BoundariesLive, as: :boundaries)
          live("/scope/:scope/:tab/:id/:section", BoundariesLive, as: :boundaries)

          live("/", BoundariesLive, as: :boundaries)
          live("/:tab", BoundariesLive, as: :boundaries)
          live("/:tab/:id", BoundariesLive, as: :boundaries)
          live("/:tab/:id/:section", BoundariesLive, as: :boundaries)
        end

        # # nested under /settings so the persistent layout treats these as settings pages
        # # (current_view will be SettingsLive / InstanceSettingsLive, which the layout's
        # # sidebar guard recognises). The actual tab rendering is delegated to the
        # # SettingsLive / InstanceSettingsLive .sface match cases.
        # scope "/settings/boundaries", Bonfire.UI.Me do
        #   pipe_through(:browser)
        #   pipe_through(:user_required)

        #   live("/:tab", SettingsLive, :user, as: :settings_boundaries)
        #   live("/:tab/:id", SettingsLive, :user, as: :settings_boundaries)
        #   live("/:tab/:id/:section", SettingsLive, :user, as: :settings_boundaries)
        # end

        # scope "/settings/instance/boundaries", Bonfire.UI.Me do
        #   pipe_through(:browser)
        #   pipe_through(:user_required)

        #   live("/:tab", InstanceSettingsLive, :instance, as: :settings_instance_boundaries)
        #   live("/:tab/:id", InstanceSettingsLive, :instance, as: :settings_instance_boundaries)

        #   live("/:tab/:id/:section", InstanceSettingsLive, :instance,
        #     as: :settings_instance_boundaries
        #   )
        # end

        # pages only admins can view
        scope "/settings/boundaries", Bonfire.UI.Boundaries do
          pipe_through(:browser)
          pipe_through(:admin_required)

          # live "/instance/", Boundaries, as: :admin_settings
        end
      end
    end
  end
end
