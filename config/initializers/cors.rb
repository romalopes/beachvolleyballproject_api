Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # origins(
    #   "https://beachvolleyballproject.vercel.app",
    #   "http://localhost:5174,
    #   http://localhost:3001"
    # )
    origins "*"
    # origins ENV.fetch("FRONTEND_URL")


    resource "*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end