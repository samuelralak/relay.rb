# frozen_string_literal: true

module Stats
  class Engine < ::Rails::Engine
    isolate_namespace Stats

    # Ensure engine can render views even in API-only host
    initializer "stats.add_view_paths" do
      ActiveSupport.on_load(:action_controller) do
        append_view_path Engine.root.join("app/views")
      end
    end

    # Include ActionView helpers
    initializer "stats.helpers" do
      ActiveSupport.on_load(:action_view) do
        include ActionView::Helpers::DateHelper
        include ActionView::Helpers::NumberHelper
      end
    end

    # Add engine paths to Rails autoload and eager_load
    # This ensures channels and jobs are loaded in both development and production
    config.autoload_paths += %W[
      #{root}/app/channels
      #{root}/app/jobs
    ]

    config.eager_load_paths += %W[
      #{root}/app/channels
      #{root}/app/jobs
    ]
  end
end
